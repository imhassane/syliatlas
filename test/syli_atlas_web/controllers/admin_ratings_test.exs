defmodule SyliAtlasWeb.AdminRatingsTest do
  use SyliAtlasWeb.ConnCase, async: false

  alias SyliAtlas.Ratings.Review

  setup %{conn: conn} do
    SyliAtlas.Geo.seed_areas!()
    SyliAtlas.Ratings.seed!()
    auth = Plug.BasicAuth.encode_basic_auth("admin", "test-password")
    {:ok, admin: put_req_header(conn, "authorization", auth)}
  end

  test "the admin asks for credentials and is not indexed", %{conn: conn} do
    conn = get(conn, "/admin/notations")
    assert conn.status == 401
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

    auth = Plug.BasicAuth.encode_basic_auth("admin", "test-password")

    build_conn()
    |> put_req_header("authorization", auth)
    |> post("/admin/notations/#{p.id}/approuver", %{
      "p" => %{"source_url" => "https://www.fitchratings.com/research/sovereigns/kenya"}
    })

    assert Review.get!(p.id).status == "approved"
  end
end
