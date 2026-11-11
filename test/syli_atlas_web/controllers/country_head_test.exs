defmodule SyliAtlasWeb.CountryHeadTest do
  @moduledoc "The header of a country profile: the same on every tab, flag, key figures."
  use SyliAtlasWeb.ConnCase, async: false

  defp doc(path), do: build_conn() |> get(path) |> html_response(200) |> LazyHTML.from_document()
  defp count(html, selector), do: html |> LazyHTML.query(selector) |> Enum.count()
  defp text(html, selector), do: html |> LazyHTML.query(selector) |> LazyHTML.text()

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    :ok
  end

  test "every tab: flag inlined, name, chips, follow, six key figures linked to their tab" do
    for tab <- ["", "/economie", "/finances-et-dette", "/marches"] do
      html = doc("/fr/pays/cote-d-ivoire" <> tab)
      assert count(html, ".country-head .flag-lg svg.flag-svg[aria-hidden=true]") == 1, tab
      assert text(html, "h1.entity-name") =~ "Côte d'Ivoire"
      assert count(html, ".entity-chips a") >= 3
      assert count(html, "#country-kpis li") == 6
    end

    html = doc("/fr/pays/cote-d-ivoire?from=2015&to=2025")
    assert text(html, "#kpi-gdp") =~ "Md$"
    assert text(html, "#kpi-gdp") =~ "depuis 2015"
    assert [href] = html |> LazyHTML.query("#kpi-debt") |> LazyHTML.attribute("href")
    assert href == "/fr/pays/cote-d-ivoire/finances-et-dette?from=2015&to=2025"
    assert text(html, "#kpi-rating") =~ "BB"
  end

  test "the period sits in the sticky tab bar, only on the tabs that use it" do
    assert count(
             doc("/fr/pays/cote-d-ivoire/economie"),
             ".tab-bar .tab-bar-period form[data-period]"
           ) == 1

    assert count(doc("/fr/pays/cote-d-ivoire/marches"), "form[data-period]") == 0
  end

  test "the answer opens the tab content, below the tab bar" do
    html = doc("/fr/pays/cote-d-ivoire/economie")
    assert count(html, ".tab-panel .tab-intro [data-answer]") == 1
    assert count(html, ".profile-head [data-answer]") == 0
  end

  test "a region: the same header, a globe instead of a flag, sections and period in the bar" do
    html = doc("/fr/regions/afrique-de-l-ouest")
    assert count(html, ".region-head .entity-mark svg") == 1
    assert count(html, ".flag") == 0
    assert text(html, "h1.entity-name") =~ "Afrique de l'Ouest"
    assert count(html, "#region-kpis li") == 6
    # Every member counts, not only the first six of the comparison query.
    assert text(html, ".entity-chips") =~ "15 pays"
    assert count(html, ".tab-bar #region-sections a[href='#economie']") == 1
    assert count(html, ".tab-bar .tab-bar-period form[data-period]") == 1
    assert count(html, ".tab-panel .tab-intro [data-answer]") == 1
  end

  test "the flag and the name sit on the same row of the header grid" do
    html = doc("/fr/pays/cote-d-ivoire")
    assert count(html, ".entity-id > .entity-mark-slot .flag-lg") == 1
    assert count(html, ".entity-id > .entity-title > h1") == 1
    assert count(html, ".entity-id > .entity-actions #follow") == 1
    assert count(html, ".entity-id > .entity-meta .entity-chips") == 1
  end

  test "every African country has its flag, inline and in the shared file" do
    sprite = File.read!(Application.app_dir(:syli_atlas, "priv/static/images/flags.svg"))

    for code <- ~w(CIV NGA ZAF EGY ETH SSD ERI SWZ) do
      assert SyliAtlasWeb.Flags.inline(code), code
      assert sprite =~ ~s(<symbol id="#{SyliAtlasWeb.Flags.iso2(code)}")
    end

    assert SyliAtlasWeb.Flags.inline("ESH") == nil
  end
end
