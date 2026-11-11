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
    api = build_conn() |> get("/api/internal/version") |> json_response(200)
    assert api["page_version"] == version
    assert String.starts_with?(version, api["build"] <> ".")
  end

  test "app manifest and service worker are served", %{conn: conn} do
    manifest = conn |> get("/manifest.webmanifest") |> response(200) |> Jason.decode!()
    assert manifest["display"] == "standalone"
    assert Enum.any?(manifest["icons"], &(&1["purpose"] == "maskable"))
    assert build_conn() |> get("/sw.js?v=test") |> response(200) =~ "skip-waiting"
  end

  test "the home page costs one SQL query: its snapshot", %{conn: conn} do
    assert_one_snapshot_query(conn, "/fr", "Md$")
  end

  test "the regions page costs one SQL query for the default period", %{conn: conn} do
    assert_one_snapshot_query(
      conn,
      "/fr/regions?indicator=inflation&focus=east_africa",
      "regions-table"
    )
  end

  test "the regions page is the same with its snapshot or computed live", %{conn: conn} do
    for path <- ["/fr/regions", "/en/regions?indicator=public_debt_pct_gdp&focus=west_africa"] do
      stored = conn |> get(path) |> html_response(200)
      SyliAtlas.Repo.query!("DELETE FROM snapshots WHERE key LIKE 'regions:%'")
      assert build_conn() |> get(path) |> html_response(200) == stored
      SyliAtlas.Profiles.Queries.refresh_snapshots!()
    end
  end

  defp assert_one_snapshot_query(conn, path, expected) do
    # The data version is kept in memory once read (here by the warm-up).
    get(build_conn(), path)
    test_pid = self()
    handler = "count-queries-#{inspect(test_pid)}"

    :telemetry.attach(
      handler,
      [:syli_atlas, :repo, :query],
      # The request runs in the test process: queries of other async tests are ignored.
      fn _event, _measures, meta, _ ->
        if self() == test_pid, do: send(test_pid, {:query, meta.query})
      end,
      nil
    )

    try do
      assert conn |> get(path) |> html_response(200) =~ expected
      queries = collect_queries([])
      assert [query] = queries, "expected one query, got:\n" <> Enum.join(queries, "\n")
      assert query =~ "FROM snapshots"
    after
      :telemetry.detach(handler)
    end
  end

  defp collect_queries(acc) do
    receive do
      {:query, q} -> collect_queries([q | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  test "the daily check updates the « last check » line of the home page", %{conn: conn} do
    at = ~U[2026-11-10 06:00:00Z]
    SyliAtlas.Profiles.Queries.touch_checked_at!(at)
    assert conn |> get("/fr") |> html_response(200) =~ "2026-11-10 06:00 UTC"
  end

  test "public pages load the site script only, never the LiveView client", %{conn: conn} do
    for path <- ["/fr", "/en/regions", "/fr/pays/cote-d-ivoire", "/fr/classement/pib"] do
      html = conn |> get(path) |> html_response(200)
      assert html =~ "/assets/js/app.js"
      refute html =~ "/assets/js/live.js", "#{path} loads the LiveView client"
    end
  end

  test "LiveViews are marked to load the LiveView client" do
    socket = %Phoenix.LiveView.Socket{}
    assert {:cont, socket} = SyliAtlasWeb.LiveAssets.on_mount(:default, %{}, %{}, socket)
    assert socket.assigns.live_js
  end

  test "the offline page lists every page that can be saved, and is not indexed", %{conn: conn} do
    html = conn |> get("/fr/hors-ligne") |> html_response(200)
    assert html =~ "Cette page n&#39;est pas encore sur cet appareil."
    assert html =~ ~s(name="robots" content="noindex")

    [json] =
      Regex.run(~r{id="offline-pages"[^>]*>(.*?)</script>}s, html, capture: :all_but_first)

    %{"pages" => pages, "strings" => strings} = Jason.decode!(json)
    assert Enum.count(pages, &(&1["kind"] == "country")) == 54
    assert %{"name" => "Sénégal"} = Enum.find(pages, &(&1["path"] == "/fr/pays/senegal"))
    assert strings["asked_area"] =~ "%{page}"

    assert build_conn() |> get("/en/offline") |> html_response(200) =~
             "This page is not on this device yet."
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
    assert redirected_to(get(conn, "/fr/regions/cote-d-ivoire"), 301) == "/fr/pays/cote-d-ivoire"
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

  test "the ranking shows the value in the arrival year by default", %{conn: conn} do
    doc = conn |> get("/fr/classement/pib") |> html_response(200) |> LazyHTML.from_document()

    assert doc
           |> LazyHTML.query(~s(select[name=mode] option[value=value][selected]))
           |> Enum.count() == 1

    # Amounts, not changes: the first row reads in dollars.
    assert doc |> LazyHTML.query("#ranking .rank-list li b") |> Enum.at(0) |> LazyHTML.text() =~
             "$"

    doc =
      build_conn()
      |> get("/fr/classement?mode=change")
      |> html_response(200)
      |> LazyHTML.from_document()

    assert doc
           |> LazyHTML.query(~s(select[name=mode] option[value=change][selected]))
           |> Enum.count() == 1

    assert doc |> LazyHTML.query("#ranking .rank-list li b") |> Enum.at(0) |> LazyHTML.text() =~
             "%"

    # The home page questions about growth still open the changes.
    home = build_conn() |> get("/fr") |> html_response(200)
    assert home =~ ~s(href="/fr/classement?mode=change")
    assert home =~ ~s(href="/fr/classement?mode=change&amp;order=asc")
  end

  test "lists show 10 rows, then pages", %{conn: conn} do
    html = conn |> get("/fr/classement/pib") |> html_response(200)
    doc = LazyHTML.from_document(html)
    assert doc |> LazyHTML.query("#ranking .rank-list li") |> Enum.count() == 10
    assert doc |> LazyHTML.query(~s(#ranking .pager a[rel="next"])) |> Enum.count() == 1

    last =
      build_conn()
      |> get("/fr/classement/pib?page=6")
      |> html_response(200)
      |> LazyHTML.from_document()

    rows = last |> LazyHTML.query("#ranking .rank-list li") |> Enum.count()
    assert rows >= 1 and rows <= 10
    assert last |> LazyHTML.query(~s(#ranking ol.rank-list[start="51"])) |> Enum.count() == 1

    # A country's region list opens on the page holding the country.
    peers =
      build_conn()
      |> get("/fr/pays/nigeria/economie")
      |> html_response(200)
      |> LazyHTML.from_document()

    assert peers |> LazyHTML.query("#peers .is-current") |> LazyHTML.text() =~ "Nigeria"
  end

  test "French typography and translations", %{conn: conn} do
    html = conn |> get("/fr/pays/cote-d-ivoire/economie") |> html_response(200)
    assert html =~ "Tous les indicateurs"
    assert build_conn() |> get("/fr/pays/cote-d-ivoire") |> html_response(200) =~ "\u202f?"
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
    assert conn |> get("/fr/classement?region=west_africa&mode=change") |> html_response(200) =~
             "Cabo Verde"

    assert redirected_to(build_conn() |> get("/fr/recherche?q=senegal")) == "/fr/pays/senegal"
    assert build_conn() |> get("/fr/methode") |> html_response(200)
  end
end
