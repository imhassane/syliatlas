defmodule SyliAtlasWeb.ProfileTabsTest do
  use SyliAtlasWeb.ConnCase, async: false

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    :ok
  end

  defp doc(path), do: build_conn() |> get(path) |> html_response(200) |> LazyHTML.from_document()
  defp has?(doc, selector), do: LazyHTML.query(doc, selector) |> Enum.count() > 0
  defp attr(doc, selector, name), do: doc |> LazyHTML.query(selector) |> LazyHTML.attribute(name)

  test "the overview: one card per tab, each linking to it, and no full tables" do
    doc = doc("/fr/pays/cote-d-ivoire")

    for {card, href} <- [
          {"economy", "/fr/pays/cote-d-ivoire/economie"},
          {"finances", "/fr/pays/cote-d-ivoire/finances-et-dette"},
          {"trade", "/fr/pays/cote-d-ivoire/commerce"},
          {"markets", "/fr/pays/cote-d-ivoire/marches"}
        ] do
      assert attr(doc, "#card-#{card}", "href") == [href], "card #{card}"
    end

    refute has?(doc, "#indicators-table")
    assert has?(doc, "#questions") and has?(doc, "#related")
  end

  test "each tab has its own canonical, hreflang, title and breadcrumb" do
    doc = doc("/fr/pays/cote-d-ivoire/commerce")

    assert attr(doc, ~s(link[rel="canonical"]), "href") == [
             "http://localhost:4000/fr/pays/cote-d-ivoire/commerce"
           ]

    assert attr(doc, ~s(link[hreflang="en"]), "href") == [
             "http://localhost:4000/en/countries/cote-d-ivoire/trade"
           ]

    # The title names what people search, with the article French needs.
    assert doc |> LazyHTML.query("title") |> LazyHTML.text() =~
             "Exportations de la Côte d'Ivoire\u202f: produits et premiers clients"

    assert doc |> LazyHTML.query(".crumbs") |> LazyHTML.text() =~ "Commerce"
    refute LazyHTML.text(LazyHTML.query(doc, ~s(script[type="application/ld+json"]))) =~ "FAQPage"
  end

  test "English tabs, French slugs redirected, unknown tab is a 404" do
    assert has?(doc("/en/countries/kenya/finances-and-debt"), "#finances")
    conn = build_conn() |> get("/en/countries/kenya/finances-et-dette")
    assert redirected_to(conn) == "/en/countries/kenya/finances-and-debt"
    assert_error_sent 404, fn -> get(build_conn(), "/fr/pays/kenya/nimporte") end
    assert get(build_conn(), "/fr/regions/afrique-de-l-ouest/commerce").status == 404
  end

  test "linking block: neighbours on the same tab, communities, other tabs" do
    doc = doc("/fr/pays/cote-d-ivoire/finances-et-dette")
    links = attr(doc, "#related a", "href")

    assert Enum.any?(
             links,
             &(&1 =~ ~r{^/fr/pays/[a-z-]+/finances-et-dette$} and
                 &1 != "/fr/pays/cote-d-ivoire/finances-et-dette")
           )

    assert "/fr/communautes/uemoa" in links
    assert "/fr/pays/cote-d-ivoire/commerce" in links
  end

  test "regions keep a single page" do
    doc = doc("/fr/regions/afrique-de-l-ouest")
    assert has?(doc, "#economie") and has?(doc, "#finances")
    refute has?(doc, "#profile-tabs")
  end
end
