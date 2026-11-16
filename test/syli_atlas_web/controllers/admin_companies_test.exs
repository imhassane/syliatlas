defmodule SyliAtlasWeb.AdminCompaniesTest do
  use SyliAtlasWeb.ConnCase, async: false
  use Oban.Testing, repo: SyliAtlas.Repo, engine: Oban.Engines.Lite

  alias SyliAtlas.{AccountsFixtures, Companies}

  @attrs %{
    "product" => "copper",
    "country" => "ZMB",
    "name" => "Test Copper Mine",
    "kind" => "mine",
    "owners" => "",
    "source_url" => "https://mine.test/",
    "source_name" => "mine.test"
  }

  setup do
    SyliAtlas.Geo.seed_areas!()
    :ok
  end

  test "lists the companies with their status and adds one, checked at once" do
    conn = AccountsFixtures.admin_conn() |> post("/admin/entreprises", %{"company" => @attrs})
    assert redirected_to(conn) == "/admin/entreprises"
    [c] = Enum.filter(Companies.list_all(), &(&1.name == "Test Copper Mine"))
    assert c.status == "pending"
    assert_enqueued(worker: SyliAtlas.Workers.CompaniesWorker, args: %{"id" => c.id})

    html = AccountsFixtures.admin_conn() |> get("/admin/entreprises") |> html_response(200)
    assert html =~ "Test Copper Mine"
    assert html =~ "À vérifier"
    assert html =~ ~s(href="/admin/entreprises" aria-current="page")
  end

  test "refuses a source that is not https" do
    conn =
      AccountsFixtures.admin_conn()
      |> post("/admin/entreprises", %{
        "company" => Map.put(@attrs, "source_url", "http://mine.test/")
      })

    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "https"
  end

  test "withdraws a company and asks for a new check" do
    {:ok, c} = Companies.create(@attrs)
    AccountsFixtures.admin_conn() |> post("/admin/entreprises/#{c.id}/retirer")
    assert Companies.get!(c.id).status == "withdrawn"

    AccountsFixtures.admin_conn() |> post("/admin/entreprises/#{c.id}/verifier")
    assert Companies.get!(c.id).status == "pending"
    assert_enqueued(worker: SyliAtlas.Workers.CompaniesWorker, args: %{"id" => c.id})
  end

  test "members and visitors are kept out", %{conn: conn} do
    assert conn |> get("/admin/entreprises") |> redirected_to() == "/fr/connexion"
  end
end
