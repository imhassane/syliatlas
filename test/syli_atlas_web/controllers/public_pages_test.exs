defmodule SyliAtlasWeb.PublicPagesTest do
  use SyliAtlasWeb.ConnCase, async: false

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    :ok
  end

  test "root redirects to a language", %{conn: conn} do
    assert redirected_to(get(conn, "/")) in ["/fr", "/en"]
  end

  test "home is cacheable and has no session", %{conn: conn} do
    conn = get(conn, "/fr")
    assert html_response(conn, 200) =~ "syli"
    assert [cache] = get_resp_header(conn, "cache-control")
    assert cache =~ "public"
    assert get_resp_header(conn, "set-cookie") == []
    refute conn.resp_body =~ "csrf-token"
  end

  test "country profile answers with the period figures", %{conn: conn} do
    html = conn |> get("/fr/pays/cote-d-ivoire") |> html_response(200)
    assert html =~ "+37,1"
    assert html =~ ~s(rel="canonical")
    assert html =~ ~s(hreflang="en")
    assert html =~ "FAQPage"

    html =
      build_conn() |> get("/en/countries/cote-d-ivoire?from=2015&to=2025") |> html_response(200)

    assert html =~ "+77.8"
  end

  test "foreign slug redirects to the canonical URL", %{conn: conn} do
    assert redirected_to(get(conn, "/fr/regions/cote-d-ivoire")) == "/fr/pays/cote-d-ivoire"
  end

  test "unknown country is a 404", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, "/fr/pays/atlantide") end
  end

  test "region and continent profiles list their members", %{conn: conn} do
    assert conn |> get("/fr/regions/afrique-de-l-ouest") |> html_response(200) =~ "Cabo Verde"
    assert build_conn() |> get("/en/regions/africa") |> html_response(200) =~ "+21.7"
  end

  test "compare adds areas and keeps them in the path", %{conn: conn} do
    assert redirected_to(get(conn, "/fr/comparer/cote-d-ivoire?add=ghana")) ==
             "/fr/comparer/cote-d-ivoire/ghana"

    html = build_conn() |> get("/fr/comparer/cote-d-ivoire/ghana") |> html_response(200)
    assert html =~ "+37,1"
    assert html =~ "+26,1"
  end

  test "ranking and search", %{conn: conn} do
    assert conn |> get("/fr/classement?region=west_africa") |> html_response(200) =~ "Cabo Verde"
    assert redirected_to(build_conn() |> get("/fr/recherche?q=senegal")) == "/fr/pays/senegal"
    assert build_conn() |> get("/fr/methode") |> html_response(200)
  end
end
