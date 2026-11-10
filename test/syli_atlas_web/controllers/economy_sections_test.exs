defmodule SyliAtlasWeb.EconomySectionsTest do
  use SyliAtlasWeb.ConnCase, async: false

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    :ok
  end

  defp doc(path), do: build_conn() |> get(path) |> html_response(200) |> LazyHTML.from_document()
  defp has?(doc, selector), do: LazyHTML.query(doc, selector) |> Enum.count() > 0

  test "a UEMOA country: section menu, public finances with the criteria, currency" do
    doc = doc("/fr/pays/cote-d-ivoire")

    for selector <- ~w(#section-nav #economie #finances #balance-chart #convergence #monnaie) do
      assert has?(doc, selector), "missing #{selector}"
    end

    text = LazyHTML.text(doc)
    assert text =~ "Critères de convergence de l'UEMOA"
    assert text =~ "655,957"
    assert text =~ "Source : FMI"

    anchors =
      doc |> LazyHTML.query("#section-nav a") |> LazyHTML.attribute("href")

    assert "#finances" in anchors and "#monnaie" in anchors and "#notation" in anchors
  end

  test "a country outside the CFA unions shows its current account instead" do
    doc = doc("/en/countries/nigeria")
    assert has?(doc, "#finances") and has?(doc, "#current-chart")
    refute has?(doc, "#convergence")
    assert LazyHTML.text(doc) =~ "no fixed peg"
  end

  test "regions get public finances, compared with Africa, but no currency" do
    doc = doc("/fr/regions/afrique-de-l-ouest")
    assert has?(doc, "#finances")
    refute has?(doc, "#monnaie")
  end

  test "the new IMF series are in the edition and in the profile" do
    assert SyliAtlas.Imports.missing_indicators() == []
    profile = SyliAtlasWeb.PublicData.area("CIV", 2020, 2025)["profile"]
    assert SyliAtlasWeb.PublicData.at(profile["series"]["fiscal_balance_pct_gdp"], 2025) == -3.0
    region = SyliAtlasWeb.PublicData.area("west_africa", 2020, 2025)["profile"]
    assert is_number(SyliAtlasWeb.PublicData.at(region["series"]["fiscal_balance_pct_gdp"], 2025))
    assert Enum.all?(region["series"]["unemployment"], &is_nil/1)
  end

  test "the method page lists every source shown, with its terms" do
    doc = doc("/fr/methode")
    assert has?(doc, "#source-imf_weo") and has?(doc, "#source-ratings")
    assert has?(doc, "#source-currencies")
    assert LazyHTML.text(doc) =~ "usage non commercial"
  end

  test "World Bank sections on a country page, each with its source" do
    doc = doc("/fr/pays/zambie")

    for selector <- ~w(#dette #creditors #flux #flow-fdi #emploi #conditions-de-vie #living-table) do
      assert has?(doc, selector), "missing #{selector}"
    end

    text = LazyHTML.text(doc)
    assert text =~ "International Debt Statistics"
    assert text =~ "OIT"
    assert "#dette" in (doc |> LazyHTML.query("#section-nav a") |> LazyHTML.attribute("href"))
  end

  test "the debt page lists the 54 countries, filters by region and sorts" do
    doc = doc("/fr/dette")
    assert doc |> LazyHTML.query("#debt-rows tbody tr") |> Enum.count() == 54
    assert LazyHTML.text(doc) =~ "Banque mondiale"

    west = doc("/fr/dette?region=west_africa&sort=china")
    assert west |> LazyHTML.query("#debt-rows tbody tr") |> Enum.count() == 15
    assert has?(west, "#debt-CIV")
    assert has?(doc("/en/debt"), "#debt-table")
  end

  test "the debt page is in the sitemap and the menu" do
    xml = build_conn() |> get("/sitemap.xml") |> response(200)
    assert xml =~ "/fr/dette"
    assert has?(doc("/fr"), ~s(a[href="/fr/dette"]))
  end

  test "trade section, with BACI as source" do
    doc = doc("/fr/pays/cote-d-ivoire")
    assert has?(doc, "#commerce") and has?(doc, "#top-exports") and has?(doc, "#top-clients")
    text = LazyHTML.text(doc)
    assert text =~ "Cacao"
    assert text =~ "CEPII, BACI"
    assert has?(doc("/fr/methode"), "#source-baci")
  end

  test "IMF risk of debt distress: on the country page and the debt page" do
    doc = doc("/fr/pays/ethiopie")
    assert has?(doc, "#debt-distress")
    assert LazyHTML.text(doc) =~ "En surendettement"
    refute has?(doc("/fr/pays/nigeria"), "#debt-distress")

    page = doc("/fr/dette?sort=risk")
    first = page |> LazyHTML.query("#debt-rows tbody tr") |> Enum.at(0) |> LazyHTML.text()
    assert first =~ "En surendettement"
  end
end
