defmodule SyliAtlasWeb.RatingsPagesTest do
  use SyliAtlasWeb.ConnCase, async: false

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    :ok
  end

  test "the ratings page lists the countries, in both languages", %{conn: conn} do
    fr = conn |> get("/fr/notations") |> html_response(200)
    assert fr =~ ~s(id="ratings-table")
    assert fr =~ ~s(id="rating-CIV")
    assert fr =~ "Notations souveraines"
    assert fr =~ "application/ld+json"

    en = build_conn() |> get("/en/credit-ratings") |> html_response(200)
    assert en =~ ~s(id="ratings-rows")
    assert en =~ "Investment grade"
  end

  test "filters by verdict and search", %{conn: conn} do
    html = conn |> get("/fr/notations?verdict=investment") |> html_response(200)
    assert html =~ ~s(id="rating-BWA")
    refute html =~ ~s(id="rating-EGY")

    html = build_conn() |> get("/fr/notations?q=zzzz") |> html_response(200)
    assert html =~ ~s(id="ratings-none")
  end

  test "a country page shows its rating and verdict", %{conn: conn} do
    path = SyliAtlasWeb.Paths.area("fr", "country", "cote-d-ivoire")
    html = conn |> get(path) |> html_response(200)
    assert html =~ ~s(id="rating-pill")
    assert html =~ ~s(id="notation")
    assert html =~ ~s(id="rating-verdict")
    assert html =~ ~s(id="climat")
    assert html =~ ~s(id="climate-wgi")
    assert html =~ "Climat des affaires"
  end

  test "a country outside B-READY says so", %{conn: conn} do
    html = conn |> get(SyliAtlasWeb.Paths.area("fr", "country", "kenya")) |> html_response(200)
    assert html =~ ~s(id="climate-bready-none")
  end

  test "a country's ratings page: verdict, history and sources", %{conn: conn} do
    html = conn |> get("/fr/notations/cote-d-ivoire") |> html_response(200)
    assert html =~ ~s(id="rating-history-rows")
    assert html =~ "<h1"
    assert html =~ "BreadcrumbList"

    assert build_conn() |> get("/en/credit-ratings/cote-d-ivoire") |> html_response(200) =~
             "Decisions"

    assert_error_sent 404, fn -> get(build_conn(), "/fr/notations/atlantide") end
  end

  test "the home page shows the ratings block", %{conn: conn} do
    html = conn |> get("/fr") |> html_response(200)
    assert html =~ ~s(id="ratings")
    assert html =~ ~s(id="ratings-top")
  end
end
