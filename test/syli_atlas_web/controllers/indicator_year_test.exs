defmodule SyliAtlasWeb.IndicatorYearTest do
  @moduledoc "Pages « PIB du Sénégal en 2025 »: one indicator, one country, one year."
  use SyliAtlasWeb.ConnCase, async: false

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    :ok
  end

  defp html(path), do: build_conn() |> get(path) |> html_response(200)

  test "the French page names the year, the value and the source" do
    {_, to} = SyliAtlas.Profiles.Builder.default_period()
    page = html("/fr/pays/senegal/pib-#{to}")
    doc = LazyHTML.from_document(page)
    title = doc |> LazyHTML.query("title") |> LazyHTML.text()

    assert title =~ "PIB du Sénégal en #{to}"
    assert title =~ "(FMI)"
    assert doc |> LazyHTML.query("#indicator-year-rows tbody tr") |> Enum.count() >= 5
    assert page =~ "Dataset"
    refute page =~ ~s(name="robots" content="noindex")
  end

  test "an address in another language goes to the canonical one" do
    {_, to} = SyliAtlas.Profiles.Builder.default_period()

    assert build_conn() |> get("/fr/pays/senegal/gdp-#{to}") |> redirected_to(301) ==
             "/fr/pays/senegal/pib-#{to}"

    assert html("/en/countries/senegal/public-debt-#{to}") =~ "Public debt of Senegal"
  end

  test "years far from now are readable but out of the index" do
    assert html("/fr/pays/senegal/croissance-2017") =~ ~s(content="noindex")
  end

  test "an unknown indicator or year is a 404" do
    assert_error_sent 404, fn -> get(build_conn(), "/fr/pays/senegal/pib-1990") end
    assert_error_sent 404, fn -> get(build_conn(), "/fr/pays/senegal/banane-2025") end
  end

  test "the figures sitemap lists the indexed years" do
    {_, to} = SyliAtlas.Profiles.Builder.default_period()
    xml = build_conn() |> get("/sitemaps/figures.xml") |> response(200)
    assert xml =~ "/fr/pays/senegal/pib-#{to}"
    refute xml =~ "/fr/pays/senegal/pib-2017"
  end
end
