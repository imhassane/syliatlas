defmodule SyliAtlasWeb.AdminBudgetsTest do
  use SyliAtlasWeb.ConnCase, async: false
  use Oban.Testing, repo: SyliAtlas.Repo, engine: Oban.Engines.Lite

  alias SyliAtlas.{BudgetFixtures, Budgets}

  setup %{conn: conn} do
    BudgetFixtures.seed!()
    {:ok, admin: SyliAtlas.AccountsFixtures.admin_conn(conn)}
  end

  defp has?(html, selector),
    do: html |> LazyHTML.from_document() |> LazyHTML.query(selector) |> Enum.count() > 0

  test "the admin asks to sign in", %{conn: conn} do
    assert redirected_to(get(conn, "/admin/budgets")) == "/fr/connexion"
    assert redirected_to(get(build_conn(), "/admin/budgets/pays")) == "/fr/connexion"
  end

  test "the queue: each proposal with its checks, a correction form and its own reject form", %{
    admin: conn
  } do
    {:ok, p} = Budgets.propose(BudgetFixtures.law_attrs(%{"currency" => "GNF"}))
    html = conn |> get("/admin/budgets") |> html_response(200)

    assert has?(html, "#budget-proposal-#{p.id}")
    assert has?(html, ~s(#admin-side a[aria-current="page"][href="/admin/budgets"]))
    assert html =~ "Devise GNF, attendue XOF"
    # An error opens the correction form.
    assert has?(html, ~s(#fix-#{p.id}[checked]))

    assert has?(
             html,
             ~s(form#reject-#{p.id}[action="/admin/budgets/propositions/#{p.id}/rejeter"])
           )

    assert has?(html, "#adm-upload-form[enctype='multipart/form-data']")
    assert has?(html, "#adm-budget-new-form")
  end

  test "proposals found by web research show their note and source", %{admin: conn} do
    assert Budgets.seed_research!() > 0
    html = conn |> get("/admin/budgets") |> html_response(200)

    assert html =~ "trouvée par recherche web"
    assert html =~ "communiqué officiel"
    assert has?(html, ~s(a[href="https://fr.apanews.net/?p=257221"]))
  end

  test "approving with the reviewer's corrections publishes the law", %{admin: conn} do
    {:ok, p} = Budgets.propose(BudgetFixtures.law_attrs(%{"stage" => "voted"}))

    conn =
      post(conn, "/admin/budgets/propositions/#{p.id}/approuver", %{
        "p" => %{"stage" => "published", "published_on" => "2026-07-17"}
      })

    assert redirected_to(conn) == "/admin/budgets"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Loi publiée."
    [law] = Budgets.list_laws("MLI")
    assert law.stage == "published"
    assert_enqueued(worker: SyliAtlas.Workers.BudgetPublishWorker)
  end

  test "approving without the official link is refused and says why", %{admin: conn} do
    {:ok, p} = Budgets.propose(BudgetFixtures.law_attrs(%{"source_url" => nil}))
    conn = post(conn, "/admin/budgets/propositions/#{p.id}/approuver", %{"p" => %{}})
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "source_url"
    assert Budgets.list_laws("MLI") == []
  end

  test "rejecting and typing a law by hand", %{admin: conn} do
    {:ok, p} = Budgets.propose(BudgetFixtures.law_attrs())
    post(conn, "/admin/budgets/propositions/#{p.id}/rejeter")
    assert Budgets.get_proposal!(p.id).status == "rejected"

    conn =
      post(conn, "/admin/budgets/propositions", %{
        "p" => BudgetFixtures.law_attrs(%{"country_code" => "STP", "currency" => "STN"})
      })

    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Loi ajoutée à la file."
    assert [%{country_code: "STP", origin: "manual"}] = Budgets.list_proposals("pending")
  end

  test "a file dropped is kept and sent to the AI, once", %{admin: conn} do
    path = Path.join(System.tmp_dir!(), "lfr-#{System.unique_integer([:positive])}.pdf")
    File.write!(path, "%PDF-1.7 loi de finances rectificative")
    upload = %Plug.Upload{path: path, filename: "lfr.pdf", content_type: "application/pdf"}

    conn =
      post(conn, "/admin/budgets/documents", %{
        "d" => %{"country_code" => "MLI", "file" => upload, "url" => ""}
      })

    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "l'IA le lit"
    [doc] = Budgets.recent_documents()
    assert doc.filename == "lfr.pdf"

    assert_enqueued(
      worker: SyliAtlas.Workers.BudgetExtractWorker,
      args: %{"document_id" => doc.id}
    )

    conn =
      post(build_admin(), "/admin/budgets/documents", %{
        "d" => %{"country_code" => "MLI", "file" => upload}
      })

    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "déjà été reçu"

    html = build_admin() |> get("/admin/budgets") |> html_response(200)
    assert has?(html, "#document-#{doc.id}")
    assert has?(html, "#reread-#{doc.id}")
  end

  test "the 54 countries and the edit of one", %{admin: conn} do
    html = conn |> get("/admin/budgets/pays") |> html_response(200)

    assert html
           |> LazyHTML.from_document()
           |> LazyHTML.query("#adm-budget-countries tbody tr")
           |> Enum.count() == 54

    html = build_admin() |> get("/admin/budgets/pays/GNB") |> html_response(200)
    assert has?(html, "#budget-country-form")

    conn =
      post(build_admin(), "/admin/budgets/pays/GNB", %{
        "c" => %{
          "legislature_fr" => "Conseil national de transition",
          "legislature_kind" => "transition",
          "collection_mode" => "auto",
          "auto_url" => "",
          "verified" => "false"
        }
      })

    # Watching needs a page: refused, the form shown again.
    assert html_response(conn, 200) =~ "auto_url"

    conn =
      post(build_admin(), "/admin/budgets/pays/GNB", %{
        "c" => %{
          "legislature_fr" => "Conseil national de transition",
          "collection_mode" => "manual",
          "verified" => "true"
        }
      })

    assert redirected_to(conn) == "/admin/budgets/pays"
    assert Budgets.get_profile("GNB").legislature_fr == "Conseil national de transition"
    assert Budgets.get_profile("GNB").verified
  end

  defp build_admin, do: SyliAtlas.AccountsFixtures.admin_conn(build_conn())
end
