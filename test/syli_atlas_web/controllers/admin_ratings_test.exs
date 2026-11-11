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
    assert html =~ ~s(id="proposal-#{p.id}")
    assert html =~ ~s(id="adm-check")
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
