defmodule SyliAtlasWeb.SiteStructureTest do
  @moduledoc "Menu, footer, sitemap, llms.txt and internal linking."
  use SyliAtlasWeb.ConnCase, async: false

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    SyliAtlasWeb.Search.Index.reset()
    :ok
  end

  defp doc(path), do: build_conn() |> get(path) |> html_response(200) |> LazyHTML.from_document()
  defp hrefs(doc, sel), do: doc |> LazyHTML.query(sel) |> LazyHTML.attribute("href")

  test "the menu: Countries, Exchanges, Themes (with the tools), and a search field" do
    doc = doc("/fr/pays/senegal")
    top = hrefs(doc, "#header-nav > a")
    assert top == ["/fr/classement/pib", "/fr/bourses"]
    themes = hrefs(doc, "#header-nav details .nav-mega-item")

    assert themes == [
             "/fr/dette",
             "/fr/budgets",
             "/fr/notations",
             "/fr/regions",
             "/fr/bourses/simulateur",
             "/fr/monnaies",
             "/fr/comparer/"
           ]

    # Each entry has its icon; the tools have their own column.
    assert doc |> LazyHTML.query("#header-nav .nav-mega-item .theme-ico svg") |> Enum.count() == 7
    assert doc |> LazyHTML.query("#header-nav .nav-mega-col") |> Enum.count() == 2

    panel = doc |> LazyHTML.query("#header-nav details") |> LazyHTML.text()
    assert panel =~ "54 pays" and panel =~ "CEDEAO"
    assert hrefs(doc, "#header-nav .nav-mega-foot a") == ["/fr/methode"]

    assert hrefs(doc, ~s(#header-nav a[aria-current="page"])) == ["/fr/classement/pib"]
    assert LazyHTML.query(doc, "#header-q[data-search-input]") |> Enum.count() == 1
    # The drawer holds every link, flat.
    assert "/fr/regions" in hrefs(doc, "#drawer-nav a")
    assert LazyHTML.query(doc, "#drawer-q[data-search-input]") |> Enum.count() == 1
  end

  test "the footer: countries, exchanges, themes, data, and the sources with the edition" do
    doc = doc("/en")
    links = hrefs(doc, ".site-footer a")
    assert "/en/countries/nigeria" in links
    assert "/en/economic-communities" in links
    assert "/llms.txt" in links and "/sitemap.xml" in links
    text = doc |> LazyHTML.query(".footer-credits") |> LazyHTML.text()
    assert text =~ "IMF (" and text =~ "CC BY 4.0" and text =~ "BACI"
    assert text =~ "not investment advice"
  end

  test "the regions page shows the communities" do
    doc = doc("/fr/regions")
    assert LazyHTML.query(doc, "#communities .community-card") |> Enum.count() == 6
    assert "/fr/communautes/uemoa" in hrefs(doc, "#communities a")
  end

  test "the sitemap lists each tab with data and the communities" do
    xml = sitemaps()
    assert xml =~ "/fr/pays/cote-d-ivoire/finances-et-dette</loc>"
    assert xml =~ ~s(hreflang="en" href="http://localhost:4000/en/countries/cote-d-ivoire/trade")
    assert xml =~ "/fr/communautes/cedeao</loc>"
    refute xml =~ "/fr/regions/afrique-de-l-ouest/"
  end

  test "llms.txt describes the site and links every country" do
    txt = build_conn() |> get("/llms.txt") |> response(200)
    assert txt =~ "# Syli Atlas"
    assert txt =~ "/en/countries/senegal"
    assert txt =~ "/api/v1/areas/SEN"
    assert txt =~ "ECOWAS"
    assert length(Regex.scan(~r{\]\(http://localhost:4000/en/countries/}, txt)) == 54
  end

  # Every page of the sitemap is linked from at least three other pages:
  # no orphan that only the sitemap knows.
  test "no orphan page" do
    pages =
      SyliAtlasWeb.SitemapController.pages()
      |> Enum.map(fn {paths, _} -> paths["fr"] end)
      |> Enum.uniq()

    inbound =
      Enum.reduce(pages, %{}, fn page, acc ->
        links =
          doc(page)
          |> hrefs("a[href^='/fr']")
          |> Enum.map(&(&1 |> String.split(["?", "#"]) |> hd() |> String.trim_trailing("/")))
          |> Enum.uniq()
          |> Enum.reject(&(&1 == String.trim_trailing(page, "/")))

        Enum.reduce(links, acc, fn l, a -> Map.update(a, l, 1, &(&1 + 1)) end)
      end)

    orphans =
      for p <- pages,
          key = String.trim_trailing(p, "/"),
          Map.get(inbound, key, 0) < 3,
          do: {p, Map.get(inbound, key, 0)}

    assert orphans == [], "linked from fewer than 3 pages: #{inspect(orphans)}"
  end
end
