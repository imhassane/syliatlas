defmodule SyliAtlasWeb.PublicPagesTest do
  use SyliAtlasWeb.ConnCase, async: false

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    :ok
  end

  test "health check", %{conn: conn} do
    assert conn |> get("/health") |> text_response(200) == "ok"
  end

  test "the page says which version it was built from, as the API does", %{conn: conn} do
    html = conn |> get("/fr") |> html_response(200)
    [_, version] = Regex.run(~r/name="syli-version" content="([^"]+)"/, html)
    api = build_conn() |> get("/api/v1/version") |> json_response(200)
    assert api["page_version"] == version
    assert String.starts_with?(version, api["build"] <> ".")
  end

  test "app manifest and service worker are served", %{conn: conn} do
    manifest = conn |> get("/manifest.webmanifest") |> response(200) |> Jason.decode!()
    assert manifest["display"] == "standalone"
    assert Enum.any?(manifest["icons"], &(&1["purpose"] == "maskable"))
    assert build_conn() |> get("/sw.js?v=test") |> response(200) =~ "skip-waiting"
  end

  test "root redirects to a language", %{conn: conn} do
    assert redirected_to(get(conn, "/")) in ["/fr", "/en"]
  end

  test "home is cacheable and has no session", %{conn: conn} do
    conn = get(conn, "/fr")
    assert html_response(conn, 200) =~ "syli"
    assert [cache] = get_resp_header(conn, "cache-control")
    assert cache == "public, no-cache"
    [etag] = get_resp_header(conn, "etag")
    assert build_conn() |> put_req_header("if-none-match", etag) |> get("/fr") |> response(304)
    assert get_resp_header(conn, "set-cookie") == []
    refute conn.resp_body =~ "csrf-token"
  end

  test "country profile answers with GDP in dollars over the period", %{conn: conn} do
    html = conn |> get("/fr/pays/cote-d-ivoire") |> html_response(200)
    assert html =~ "99,9 Md$"
    assert html =~ "+58,3"
    assert html =~ ~s(rel="canonical")
    assert html =~ ~s(hreflang="en")
    assert html =~ "FAQPage"

    html =
      build_conn() |> get("/en/countries/cote-d-ivoire?from=2015&to=2025") |> html_response(200)

    assert html =~ "+118.0"
  end

  test "foreign slug redirects to the canonical URL", %{conn: conn} do
    assert redirected_to(get(conn, "/fr/regions/cote-d-ivoire")) == "/fr/pays/cote-d-ivoire"
  end

  test "unknown country is a 404", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, "/fr/pays/atlantide") end
  end

  test "region and continent profiles list their members", %{conn: conn} do
    assert conn |> get("/fr/regions/afrique-de-l-ouest") |> html_response(200) =~ "Cabo Verde"
    assert build_conn() |> get("/en/regions/africa") |> html_response(200) =~ "+17.6"
  end

  test "compare adds areas and keeps them in the path", %{conn: conn} do
    assert redirected_to(get(conn, "/fr/comparer/cote-d-ivoire?add=ghana")) ==
             "/fr/comparer/cote-d-ivoire/ghana"

    html = build_conn() |> get("/fr/comparer/cote-d-ivoire/ghana") |> html_response(200)
    assert html =~ "+58,3"
    assert html =~ "+63,8"
  end

  test "lists show 10 rows, then pages", %{conn: conn} do
    html = conn |> get("/fr/classement") |> html_response(200)
    doc = LazyHTML.from_document(html)
    assert doc |> LazyHTML.query("#ranking .rank-list li") |> Enum.count() == 10
    assert doc |> LazyHTML.query(~s(#ranking .pager a[rel="next"])) |> Enum.count() == 1

    last =
      build_conn()
      |> get("/fr/classement?page=6")
      |> html_response(200)
      |> LazyHTML.from_document()

    rows = last |> LazyHTML.query("#ranking .rank-list li") |> Enum.count()
    assert rows >= 1 and rows <= 10
    assert last |> LazyHTML.query(~s(#ranking ol.rank-list[start="51"])) |> Enum.count() == 1

    # A country's region list opens on the page holding the country.
    peers =
      build_conn() |> get("/fr/pays/nigeria") |> html_response(200) |> LazyHTML.from_document()

    assert peers |> LazyHTML.query("#peers .is-current") |> LazyHTML.text() =~ "Nigeria"
  end

  test "French typography and translations", %{conn: conn} do
    html = conn |> get("/fr/pays/cote-d-ivoire") |> html_response(200)
    assert html =~ "Tous les indicateurs"
    assert html =~ "\u202f?"
  end

  test "home map: every country links to its profile, the panel shows GDP in dollars", %{
    conn: conn
  } do
    doc = conn |> get("/fr") |> html_response(200) |> LazyHTML.from_document()
    links = LazyHTML.query(doc, "#africa-map a.cty")
    assert Enum.count(links) == 54

    assert doc |> LazyHTML.query(~s(#africa-map a[data-code="KEN"])) |> LazyHTML.attribute("href") ==
             ["/fr/pays/kenya"]

    assert doc |> LazyHTML.query(~s(#map-panel [data-field="name"])) |> LazyHTML.text() =~
             "Côte d'Ivoire"

    assert doc |> LazyHTML.query(~s(#map-panel [data-field="gdp"])) |> LazyHTML.text() =~ "Md$"
    assert doc |> LazyHTML.query("#map-data") |> Enum.count() == 1
  end

  test "home map: another indicator through the URL, without JavaScript", %{conn: conn} do
    doc = conn |> get("/fr?carte=inflation") |> html_response(200) |> LazyHTML.from_document()

    assert doc
           |> LazyHTML.query(~s(#africa-map a[data-code="NGA"]))
           |> LazyHTML.attribute("class")
           |> hd() =~ "q-bad-"

    assert doc
           |> LazyHTML.query(~s([data-map-indicator="inflation"][aria-current="true"]))
           |> Enum.count() == 1
  end

  test "regions page compares the five regions", %{conn: conn} do
    doc = conn |> get("/fr/regions") |> html_response(200) |> LazyHTML.from_document()
    assert doc |> LazyHTML.query("#regions-table tbody tr") |> Enum.count() == 7
    assert doc |> LazyHTML.query("#regions-map a.cty.rf-west_africa") |> Enum.count() > 10
    assert doc |> LazyHTML.query(".carry-card") |> Enum.count() == 5

    focused =
      build_conn()
      |> get("/en/regions?indicator=inflation&focus=east_africa")
      |> html_response(200)
      |> LazyHTML.from_document()

    assert focused |> LazyHTML.query("#regions-map a.cty.rf-west_africa") |> Enum.count() == 0

    assert focused |> LazyHTML.query(".region-chips a[aria-current]") |> LazyHTML.text() =~
             "East Africa"
  end

  test "ranking and search", %{conn: conn} do
    assert conn |> get("/fr/classement?region=west_africa") |> html_response(200) =~ "Cabo Verde"
    assert redirected_to(build_conn() |> get("/fr/recherche?q=senegal")) == "/fr/pays/senegal"
    assert build_conn() |> get("/fr/methode") |> html_response(200)
  end
end
