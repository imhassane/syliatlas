defmodule SyliAtlasWeb.AdminRatingsTest do
  use SyliAtlasWeb.ConnCase, async: false

  alias SyliAtlas.Ratings.Review

  setup %{conn: conn} do
    SyliAtlas.Geo.seed_areas!()
    SyliAtlas.Ratings.seed!()
    {:ok, admin: SyliAtlas.AccountsFixtures.admin_conn(conn)}
  end

  test "the admin asks to sign in and is not indexed", %{conn: conn} do
    conn = get(conn, "/admin/notations")
    assert redirected_to(conn) == "/fr/connexion"
    assert get_resp_header(conn, "x-robots-tag") == ["noindex, nofollow"]
  end

  test "lists the queue and the rows to check", %{admin: conn} do
    {:ok, p} =
      Review.propose(%{
        "country_code" => "KEN",
        "agency" => "fitch",
        "rating" => "B",
        "action_date" => "2026-11-01"
      })

    html = conn |> get("/admin/notations") |> html_response(200)
    doc = LazyHTML.from_document(html)
    assert html =~ ~s(id="proposal-#{p.id}")
    assert html =~ ~s(id="adm-check")
    # Layout of the mockup: admin menu, key figures, entry form behind a button.
    refute Enum.empty?(
             LazyHTML.query(doc, ~s(#adm-bar a[aria-current="page"][href="/admin/notations"]))
           )

    refute Enum.empty?(LazyHTML.query(doc, "#adm-stats"))
    refute Enum.empty?(LazyHTML.query(doc, ~s(label[for="adm-new-toggle"])))
    # Reject has its own form, reached from the button by its form attribute.
    refute Enum.empty?(LazyHTML.query(doc, ~s(button[form="reject-#{p.id}"])))

    refute Enum.empty?(
             LazyHTML.query(
               doc,
               ~s(form#reject-#{p.id}[action="/admin/notations/#{p.id}/rejeter"])
             )
           )
  end

  test "filters the queue: rating changes or confirmations", %{admin: conn} do
    current = SyliAtlas.Ratings.for_country(SyliAtlas.Ratings.document(), "KEN")
    fitch = Enum.find(current["agencies"], &(&1["agency"] == "fitch"))

    {:ok, same} =
      Review.propose(%{
        "country_code" => "KEN",
        "agency" => "fitch",
        "rating" => fitch["rating"],
        "action_type" => "affirmed",
        "action_date" => "2026-11-02"
      })

    {:ok, change} =
      Review.propose(%{
        "country_code" => "KEN",
        "agency" => "fitch",
        "rating" => "CCC",
        "action_type" => "downgrade",
        "action_date" => "2026-11-03"
      })

    changes = conn |> get("/admin/notations?filtre=changements") |> html_response(200)
    assert changes =~ ~s(id="proposal-#{change.id}")
    refute changes =~ ~s(id="proposal-#{same.id}")

    confs =
      SyliAtlas.AccountsFixtures.admin_conn()
      |> get("/admin/notations?filtre=confirmations")
      |> html_response(200)

    assert confs =~ ~s(id="proposal-#{same.id}")
    refute confs =~ ~s(id="proposal-#{change.id}")
  end

  test "an empty queue says when the next watch runs", %{admin: conn} do
    html = conn |> get("/admin/notations") |> html_response(200)
    assert html =~ ~s(id="adm-empty")
  end

  test "the other admin pages share the admin menu", %{admin: conn} do
    html = conn |> get("/admin/recherches") |> html_response(200)
    assert html =~ ~s(id="adm-bar")
  end

  test "a typed decision joins the queue, then is published", %{admin: conn} do
    conn =
      post(conn, "/admin/notations", %{
        "p" => %{
          "country_code" => "KEN",
          "agency" => "fitch",
          "rating" => "B",
          "action_date" => "2026-11-01",
          "action_type" => "affirmed"
        }
      })

    assert redirected_to(conn) == "/admin/notations"
    [p] = Review.list("pending")

    SyliAtlas.AccountsFixtures.admin_conn()
    |> post("/admin/notations/#{p.id}/approuver", %{
      "p" => %{"source_url" => "https://www.fitchratings.com/research/sovereigns/kenya"}
    })

    assert Review.get!(p.id).status == "approved"
  end
end
