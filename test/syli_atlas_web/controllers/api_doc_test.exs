defmodule SyliAtlasWeb.ApiDocTest do
  use SyliAtlasWeb.ConnCase, async: false

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    SyliAtlas.ApiTimings.reset()
    :ok
  end

  defp doc(html), do: LazyHTML.from_document(html)

  test "the API page, in French and English, with every route", %{conn: conn} do
    html = conn |> get(~p"/fr/api") |> html_response(200)
    page = doc(html)

    for id <- ~w(areas area compare ranking indicators csv) do
      assert LazyHTML.query(page, "#route-#{id}") |> Enum.count() == 1
    end

    assert html =~ "Syli Atlas API"
    assert html =~ "https://" or html =~ "http://"
    assert LazyHTML.query(page, "#erreurs") |> Enum.count() == 1
    assert LazyHTML.query(page, "#performance") |> Enum.count() == 1
    assert html =~ "Temps total : ça dépend du pays"

    en = build_conn() |> get(~p"/en/api") |> html_response(200)
    assert en =~ "Total time: it depends on the country"
    assert LazyHTML.query(doc(en), "#errors") |> Enum.count() == 1
  end

  test "examples are real answers, coloured, in four languages", %{conn: conn} do
    page = conn |> get(~p"/fr/api") |> html_response(200) |> doc()
    area = LazyHTML.query(page, "#route-area")

    assert area |> LazyHTML.query(".code-pane") |> Enum.count() == 4
    assert area |> LazyHTML.query("input[type=radio][checked]") |> Enum.count() == 1
    text = LazyHTML.text(area)
    assert text =~ "\"CIV\""
    assert text =~ "\"change_percent\""
    assert area |> LazyHTML.query(".tok-key") |> Enum.count() > 5
    assert LazyHTML.query(page, "#route-csv") |> LazyHTML.text() =~ "year,status"
  end

  test "code lines carry no stray space or line break", %{conn: conn} do
    html = conn |> get(~p"/fr/api") |> html_response(200)
    assert html =~ ~s(<li><span class="tok-)
    refute html =~ ~r/<li>\s+<span class="tok-/
    refute html =~ ~r/<\/span>\s+<span class="tok-/
    # Text is escaped.
    assert html =~ "&quot;CIV&quot;" or html =~ "&#34;CIV&#34;"
  end

  test "server time: empty before the first hour, then per route", %{conn: conn} do
    html = conn |> get(~p"/fr/api") |> html_response(200)
    assert html =~ "Mesures en cours"

    past = DateTime.add(DateTime.utc_now(), -1, :hour)
    for us <- [900, 1200, 1500], do: SyliAtlas.ApiTimings.record("area", us, past)
    SyliAtlas.ApiTimings.record("csv", 25_000, past)
    SyliAtlas.ApiTimings.flush()

    page = build_conn() |> get(~p"/fr/api") |> html_response(200) |> doc()
    perf = LazyHTML.query(page, "#performance") |> LazyHTML.text()
    assert perf =~ "1,2 ms"
    assert perf =~ "dans le budget"
    assert perf =~ "au-dessus du budget"
    assert LazyHTML.query(page, "#performance svg.api-spark") |> Enum.count() == 2
  end

  test "every field of every answer is in the page, with the closed lists", %{conn: conn} do
    page = conn |> get(~p"/fr/api") |> html_response(200) |> doc()

    fields = page |> LazyHTML.query("#fields-area .api-fpath") |> Enum.map(&LazyHTML.text/1)
    assert "data.kind" in fields and "data.period" in fields and "meta.sources" in fields

    kind = page |> LazyHTML.query("#values-kind") |> LazyHTML.text()
    for v <- ~w(country region continent imf_aggregate), do: assert(kind =~ v)

    assert page |> LazyHTML.query("#schema-Series .api-fpath") |> Enum.count() == 11
    indicators = page |> LazyHTML.query("#indicateurs") |> LazyHTML.text()
    assert indicators =~ "public_debt_pct_gdp" and indicators =~ "% du PIB"

    en = build_conn() |> get(~p"/en/api") |> html_response(200) |> doc()
    assert en |> LazyHTML.query("#indicators") |> LazyHTML.text() =~ "% of GDP"
  end

  test "the page answers 304 while nothing changed", %{conn: conn} do
    first = get(conn, ~p"/fr/api")
    [etag] = get_resp_header(first, "etag")
    assert get_resp_header(first, "cache-control") == ["public, no-cache"]

    assert build_conn()
           |> put_req_header("if-none-match", etag)
           |> get(~p"/fr/api")
           |> response(304)
  end

  test "the footer and the sitemap lead to the page", %{conn: conn} do
    home = conn |> get(~p"/fr") |> html_response(200)
    assert home =~ ~s(href="/fr/api")
    refute home =~ ~s(href="/api/v1/areas")

    sitemap = sitemaps()
    assert sitemap =~ "/fr/api</loc>"
    assert sitemap =~ "/en/api"
  end
end
