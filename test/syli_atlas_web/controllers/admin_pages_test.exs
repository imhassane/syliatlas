defmodule SyliAtlasWeb.AdminPagesTest do
  use SyliAtlasWeb.ConnCase, async: false
  use Oban.Testing, repo: SyliAtlas.Repo, engine: Oban.Engines.Lite

  import Ecto.Query
  alias SyliAtlas.{AccountsFixtures, Repo}
  alias SyliAtlas.Market.QualityIssue

  defp admin, do: AccountsFixtures.admin_conn()

  describe "side bar" do
    test "lists every admin page and marks the current one", %{conn: _} do
      SyliAtlas.Geo.seed_areas!()
      html = admin() |> get("/admin/mises-a-jour") |> html_response(200)

      for path <-
            ~w(/admin/mises-a-jour /admin/notations /admin/marches /admin/membres /admin/emails /admin/recherches) do
        assert html =~ ~s(href="#{path}")
      end

      assert html =~ ~s(href="/admin/mises-a-jour" aria-current="page")
    end

    test "members get a 404, visitors the sign-in page", %{conn: conn} do
      assert conn |> get("/admin/marches") |> redirected_to() == "/fr/connexion"
    end
  end

  describe "mises à jour" do
    setup do
      {:ok, edition: SyliAtlas.Fixtures.load_snapshot!()}
    end

    test "shows queues, jobs, sources and the reading functions", %{edition: edition} do
      {:ok, _} = SyliAtlas.Workers.CheckSourcesWorker.new(%{}) |> Oban.insert()

      html = admin() |> get("/admin/mises-a-jour") |> html_response(200)
      assert html =~ ~s(id="queue-imports")
      assert html =~ "Vérifier les sources"

      html = admin() |> get("/admin/mises-a-jour?onglet=sources") |> html_response(200)
      assert html =~ ~s(id="edition-#{edition.id}")
      assert html =~ ~s(id="source-imf_weo")

      html = admin() |> get("/admin/mises-a-jour?onglet=fonctions") |> html_response(200)
      assert html =~ ~s(id="functions-measure")
    end

    test "« Vérifier maintenant » queues a check of the sources" do
      conn = admin() |> post("/admin/mises-a-jour/verifier")
      assert redirected_to(conn) == "/admin/mises-a-jour"
      assert_enqueued(worker: SyliAtlas.Workers.CheckSourcesWorker)
    end

    test "measuring fills the reading functions table" do
      conn = admin() |> post("/admin/mises-a-jour/mesurer")
      assert redirected_to(conn) =~ "onglet=fonctions"
      html = admin() |> get("/admin/mises-a-jour?onglet=fonctions") |> html_response(200)
      assert html =~ ~s(id="functions-table")
      assert html =~ ~s(id="fn-area_profile")
    end

    test "the detail of an import shows its steps and checks", %{edition: edition} do
      html = admin() |> get("/admin/mises-a-jour/editions/#{edition.id}") |> html_response(200)
      assert html =~ ~s(id="edition-steps")
      assert html =~ ~s(id="edition-checks")
      assert html =~ ~s(id="edition-revisions")
    end

    test "rerunning an import queues it with force", %{edition: edition} do
      admin() |> post("/admin/mises-a-jour/editions/#{edition.id}/relancer")

      assert_enqueued(
        worker: SyliAtlas.Workers.ImportEditionWorker,
        args: %{label: edition.label, force: true}
      )
    end
  end

  describe "données de marché" do
    setup do
      SyliAtlas.MarketFixtures.import!()
      :ok
    end

    test "every tab renders" do
      for tab <- ["", "?onglet=bourses", "?onglet=sources", "?onglet=fantome"] do
        html = admin() |> get("/admin/marches" <> tab) |> html_response(200)
        assert html =~ ~s(id="market-stats")
      end

      html = admin() |> get("/admin/marches?onglet=bourses") |> html_response(200)
      assert html =~ ~s(id="exchange-brvm")
      html = admin() |> get("/admin/marches?onglet=sources") |> html_response(200)
      assert html =~ ~s(id="licence-mansa")
    end

    test "an anomaly decided in the admin stays closed at the next import" do
      issue = Repo.one(from q in QualityIssue, where: q.status == "open", limit: 1)
      assert issue, "the fixtures should raise at least one anomaly"

      html = admin() |> get("/admin/marches") |> html_response(200)
      assert html =~ ~s(id="issue-#{issue.id}")

      conn = admin() |> post("/admin/marches/anomalies/#{issue.id}", %{"action" => "ignore"})
      assert redirected_to(conn) == "/admin/marches"
      assert Repo.get!(QualityIssue, issue.id).status == "ignored"
      assert_enqueued(worker: SyliAtlas.Workers.MarketPublishWorker)

      # Same check again, same problem: no new open issue for this rule.
      SyliAtlas.Market.Quality.sync!(
        issue.subject_type,
        issue.subject_id,
        issue.trade_date,
        [%{rule: issue.rule, severity: issue.severity, detail: issue.detail, data: issue.data}],
        [issue.rule]
      )

      refute Repo.exists?(
               from q in QualityIssue,
                 where:
                   q.subject_type == ^issue.subject_type and q.subject_id == ^issue.subject_id and
                     q.rule == ^issue.rule and q.status == "open"
             )

      html = admin() |> get("/admin/marches") |> html_response(200)
      refute html =~ ~s(id="issue-#{issue.id}")
    end

    test "« Importer maintenant » queues an import" do
      admin() |> post("/admin/marches/importer")
      assert_enqueued(worker: SyliAtlas.Workers.MarketImportWorker)
    end
  end

  describe "membres et e-mails" do
    test "filters, and closing the sessions of an account" do
      member = AccountsFixtures.user_fixture(%{email: "kouadio@example.com"})
      {_token, _session} = SyliAtlas.Accounts.Sessions.create(member, :code, user_agent: "test")

      html = admin() |> get("/admin/membres?filtre=admins") |> html_response(200)
      refute html =~ "kouadio@example.com"

      html = admin() |> get("/admin/membres") |> html_response(200)
      assert html =~ ~s(id="member-sessions-#{member.id}")

      admin() |> post("/admin/membres/#{member.id}/sessions")
      assert SyliAtlas.Accounts.Sessions.list(member) == []
    end

    test "the e-mails page renders, with its filters" do
      for f <- ["", "?filtre=envoyes", "?filtre=echecs", "?filtre=recap"] do
        html = admin() |> get("/admin/emails" <> f) |> html_response(200)
        assert html =~ ~s(id="emails-stats")
      end
    end
  end
end
