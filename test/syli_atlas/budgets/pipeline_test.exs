defmodule SyliAtlas.Budgets.PipelineTest do
  use SyliAtlas.DataCase, async: false
  use Oban.Testing, repo: SyliAtlas.Repo, engine: Oban.Engines.Lite

  alias SyliAtlas.{BudgetFixtures, Budgets}
  alias SyliAtlas.Budgets.{Extractor, Proposal}
  alias SyliAtlas.Workers.{BudgetExtractWorker, BudgetFetchWorker, BudgetPublishWorker}

  setup do
    BudgetFixtures.seed!()
    :ok
  end

  defp claude(laws) do
    Req.Test.stub(Extractor, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(self(), {:claude, Jason.decode!(body)})

      Req.Test.json(conn, %{
        "content" => [
          %{"type" => "tool_use", "name" => "record_budget_laws", "input" => %{"laws" => laws}}
        ]
      })
    end)
  end

  @law %{
    "fiscal_year" => 2026,
    "kind" => "initial",
    "stage" => "published",
    "reference" => "L/2026/010/CNT",
    "legislature" => "Conseil National de la Transition",
    "voted_on" => "2026-03-31",
    "published_on" => "2026-03-31",
    "revenue" => "53 412 000 000 000",
    "expenditure" => "64 118 000 000 000",
    "currency" => "GNF",
    "revenue_page" => "p. 3, article 2",
    "expenditure_page" => "p. 4, article 3",
    "excerpt" => "Les charges du budget de l'État sont fixées à…"
  }

  test "a PDF dropped in the admin is read by the AI and lands in the queue, with its pages" do
    claude([@law])

    {:ok, doc, :new} =
      Budgets.store_document("GIN", "upload", %{
        body: "%PDF-1.7 JO",
        content_type: "application/pdf",
        filename: "jo.pdf"
      })

    assert :ok =
             perform_job(BudgetExtractWorker, %{
               "document_id" => doc.id,
               "model" => Extractor.model()
             })

    assert_received {:claude, request}

    [
      %{
        "content" => [
          %{"type" => "document", "source" => %{"media_type" => "application/pdf"}} | _
        ]
      }
    ] = request["messages"]

    assert request["system"] =~ "Guinea (GIN)"
    assert request["system"] =~ "GNF"

    [p] = Budgets.list_proposals("pending")
    assert p.origin == "extraction"
    assert p.document_id == doc.id
    assert Decimal.equal?(p.expenditure, Decimal.new("64118000000000"))
    assert p.evidence["expenditure"] == "p. 4, article 3"
    assert p.model == Extractor.model()
    assert Budgets.get_document!(doc.id).status == "extracted"
  end

  test "a web page is sent as text, without its scripts" do
    claude([])
    html = "<html><script>var x=1</script><body><h1>Loi de finances</h1></body></html>"

    {:ok, doc, :new} =
      Budgets.store_document("SEN", "upload", %{
        body: html,
        content_type: "text/html",
        filename: "loi.html"
      })

    assert :ok = perform_job(BudgetExtractWorker, %{"document_id" => doc.id, "model" => "m"})

    assert_received {:claude,
                     %{"messages" => [%{"content" => [%{"type" => "text", "text" => text}]}]}}

    assert text =~ "Loi de finances"
    refute text =~ "var x"
    assert Budgets.get_document!(doc.id).error == "no budget law found"
    assert Repo.aggregate(Proposal, :count) == 0
  end

  test "without a key, the document waits and laws are typed by hand" do
    previous = Application.get_env(:syli_atlas, Extractor)
    Application.put_env(:syli_atlas, Extractor, Keyword.put(previous, :api_key, nil))
    on_exit(fn -> Application.put_env(:syli_atlas, Extractor, previous) end)

    {:ok, doc, :new} =
      Budgets.store_document("MLI", "upload", %{body: "%PDF x", content_type: "application/pdf"})

    assert {:cancel, :no_api_key} =
             perform_job(BudgetExtractWorker, %{"document_id" => doc.id, "model" => "m"})

    assert Budgets.get_document!(doc.id).status == "no_key"
  end

  test "a document is read once per model unless an administrator asks again" do
    {:ok, doc, :new} =
      Budgets.store_document("MLI", "upload", %{body: "%PDF y", content_type: "application/pdf"})

    {:ok, first} = BudgetExtractWorker.enqueue(doc)
    {:ok, dup} = BudgetExtractWorker.enqueue(doc)
    assert dup.conflict?
    {:ok, again} = BudgetExtractWorker.enqueue(doc, again: true)
    refute again.conflict?
    refute again.id == first.id
  end

  test "a watched page: new PDF links are fetched, stored and sent to the AI" do
    profile = Budgets.get_profile!("MLI")

    {:ok, _} =
      Budgets.update_profile(profile, %{
        "collection_mode" => "auto",
        "auto_url" => "https://sgg-mali.ml/JO/2026/"
      })

    Req.Test.stub(BudgetFetchWorker, fn
      %{request_path: "/JO/2026/"} = conn ->
        Plug.Conn.send_resp(
          conn,
          200,
          ~s(<a href="mali-jo-2026-15.pdf">JO 15</a> <a href="/about">x</a> <a href="https://sgg-mali.ml/JO/2026/mali-jo-2026-14.pdf">JO 14</a>)
        )

      conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/pdf")
        |> Plug.Conn.send_resp(200, "%PDF " <> conn.request_path)
    end)

    assert :ok = perform_job(BudgetFetchWorker, %{})
    assert_enqueued(worker: BudgetFetchWorker, args: %{"country_code" => "MLI"})
    assert :ok = perform_job(BudgetFetchWorker, %{"country_code" => "MLI"})

    urls = Budgets.recent_documents() |> Enum.map(& &1.url) |> Enum.sort()

    assert urls == [
             "https://sgg-mali.ml/JO/2026/mali-jo-2026-14.pdf",
             "https://sgg-mali.ml/JO/2026/mali-jo-2026-15.pdf"
           ]

    assert Enum.all?(Budgets.recent_documents(), &(&1.content_type == "application/pdf"))
    assert length(all_enqueued(worker: BudgetExtractWorker)) == 2

    # Next morning: nothing new.
    assert :ok = perform_job(BudgetFetchWorker, %{"country_code" => "MLI"})
    assert length(Budgets.recent_documents()) == 2
  end

  test "links: relative ones resolved, the pattern applied" do
    html = ~s(<a href="a.pdf">1</a><a href='/x/LFR-2026.pdf'>2</a><a href="b.html">3</a>)

    assert BudgetFetchWorker.links(html, "https://jo.example/2026/", nil) ==
             ["https://jo.example/2026/a.pdf", "https://jo.example/x/LFR-2026.pdf"]

    assert BudgetFetchWorker.links(html, "https://jo.example/2026/", "lfr") == [
             "https://jo.example/x/LFR-2026.pdf"
           ]
  end

  describe "alerts" do
    setup do
      user = SyliAtlas.AccountsFixtures.user_fixture()

      {:ok, alert} =
        SyliAtlas.Accounts.Alerts.create(user, %{"kind" => "budget_law", "area_code" => "MLI"})

      {:ok, user: user, alert: alert}
    end

    test "a published law alerts the followers of its country, once per stage", %{alert: alert} do
      law = BudgetFixtures.publish!()
      assert :ok = perform_job(BudgetPublishWorker, %{"type" => "law", "law_id" => law.id})

      assert_enqueued(
        worker: SyliAtlas.Workers.AlertEventWorker,
        args: %{"type" => "budget_law", "law_id" => law.id}
      )

      assert SyliAtlas.Accounts.AlertEvents.on_budget_law(law.id) == 1
      assert SyliAtlas.Accounts.AlertEvents.on_budget_law(law.id) == 0

      [delivery] = Repo.all(SyliAtlas.Accounts.AlertDelivery)
      assert delivery.alert_id == alert.id
      assert delivery.payload["expenditure"] == "3993319000000"

      email = SyliAtlas.Accounts.AlertEmails.alert(Repo.preload(alert, :user).user, delivery)
      assert email.subject =~ "Mali"
      assert email.text_body =~ "3 993 Md XOF" or email.text_body =~ "3 993 Md XOF"
      assert email.text_body =~ "sgg-mali.ml"
      assert email.text_body =~ "/fr/pays/mali/budget"

      law = BudgetFixtures.publish!(%{"stage" => "published", "published_on" => "2026-07-17"})
      assert SyliAtlas.Accounts.AlertEvents.on_budget_law(law.id) == 1
    end

    test "a new IMF edition does not trigger budget alerts", %{alert: _alert} do
      edition = SyliAtlas.Fixtures.load_snapshot!()
      assert SyliAtlas.Accounts.AlertEvents.on_edition(edition.id) == 0
    end
  end
end
