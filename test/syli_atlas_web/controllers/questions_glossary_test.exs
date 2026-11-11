defmodule SyliAtlasWeb.QuestionsGlossaryTest do
  use SyliAtlasWeb.ConnCase, async: false

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    :ok
  end

  defp doc(path), do: build_conn() |> get(path) |> html_response(200) |> LazyHTML.from_document()
  defp text(doc, sel), do: doc |> LazyHTML.query(sel) |> LazyHTML.text()

  test "each country has a page of questions answered from the data" do
    d = doc("/fr/pays/cote-d-ivoire/questions")
    assert text(d, "h1") =~ "Questions sur l'économie de la Côte d'Ivoire"
    assert LazyHTML.query(d, "#country-questions li") |> Enum.count() >= 8
    assert text(d, "#q-currency") =~ "XOF"
    assert text(d, "#q-gdp") =~ "Md$"
    assert text(d, "#q-rich h2") =~ "La Côte d'Ivoire, un pays riche"

    json =
      d
      |> LazyHTML.query(~s(script[type="application/ld+json"]))
      |> Enum.map(&Jason.decode!(LazyHTML.text(&1)))

    assert Enum.any?(json, &(&1["@type"] == "FAQPage" and length(&1["mainEntity"]) >= 8))

    assert text(doc("/en/countries/kenya/questions"), "h1") =~ "Questions on the economy of Kenya"

    assert redirected_to(get(build_conn(), "/fr/pays/cote-d-ivoire/questions/"), 301) =~
             "/fr/pays/cote-d-ivoire/questions"

    assert_error_sent 404, fn -> get(build_conn(), "/fr/pays/atlantide/questions") end
  end

  test "the overview links its questions; the sitemap lists them" do
    links =
      doc("/fr/pays/senegal") |> LazyHTML.query("#all-questions") |> LazyHTML.attribute("href")

    assert links == ["/fr/pays/senegal/questions"]
    assert sitemaps() =~ "/fr/pays/senegal/questions</loc>"
  end

  test "the glossary defines each notion with the figures of the day" do
    index = doc("/fr/glossaire")

    assert LazyHTML.query(index, "#glossary dt") |> Enum.count() ==
             length(SyliAtlasWeb.GlossaryController.terms())

    d = doc("/fr/glossaire/parite-de-pouvoir-d-achat")
    assert text(d, "h1") =~ "Parité de pouvoir d'achat"
    assert text(d, "#definition") =~ "acheter"
    assert text(d, "#term-figures-table") =~ "Médiane des pays africains"

    json =
      d
      |> LazyHTML.query(~s(script[type="application/ld+json"]))
      |> Enum.map(&Jason.decode!(LazyHTML.text(&1)))

    assert Enum.any?(json, &(&1["@type"] == "DefinedTerm"))

    assert redirected_to(get(build_conn(), "/fr/glossaire/purchasing-power-parity"), 301) ==
             "/fr/glossaire/parite-de-pouvoir-d-achat"

    for id <- SyliAtlasWeb.GlossaryController.terms(), locale <- ~w(fr en) do
      assert get(build_conn(), SyliAtlasWeb.GlossaryController.term_path(locale, id)).status ==
               200
    end
  end
end
