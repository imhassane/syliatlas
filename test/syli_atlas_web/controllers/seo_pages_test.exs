defmodule SyliAtlasWeb.SeoPagesTest do
  @moduledoc """
  Pages written for search (thematic rankings, pairs, questions, about), the
  metadata every page carries, and what crawlers read (sitemaps, robots,
  llms-full.txt). From the audit of 11 November 2026.
  """
  use SyliAtlasWeb.ConnCase, async: false

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    :ok
  end

  defp doc(path), do: build_conn() |> get(path) |> html_response(200) |> LazyHTML.from_document()
  defp text(doc, sel), do: doc |> LazyHTML.query(sel) |> LazyHTML.text()

  defp json_ld(doc) do
    doc
    |> LazyHTML.query(~s(script[type="application/ld+json"]))
    |> Enum.map(&(&1 |> LazyHTML.text() |> Jason.decode!()))
  end

  defp types(doc), do: doc |> json_ld() |> Enum.map(& &1["@type"])

  describe "titles and sentences" do
    test "French titles carry the article and the words people search" do
      assert text(doc("/fr/pays/senegal"), "title") =~
               "Sénégal : PIB, croissance, dette et inflation"

      assert text(doc("/fr/notations/senegal"), "title") =~ "Note souveraine du Sénégal"

      assert text(doc("/fr/pays/cote-d-ivoire/finances-et-dette"), "title") =~
               "Dette publique de la Côte d'Ivoire"

      faq = doc("/fr/pays/egypte") |> json_ld() |> Enum.find(&(&1["@type"] == "FAQPage"))
      questions = Enum.map(faq["mainEntity"], & &1["name"])
      assert Enum.any?(questions, &(&1 =~ "PIB par habitant de l'Égypte"))
      refute Enum.any?(questions, &(&1 =~ ~r/\bde (Égypte|Sénégal)\b/))
    end

    test "each tab has a description of its own" do
      overview =
        doc("/fr/pays/kenya")
        |> LazyHTML.query(~s(meta[name="description"]))
        |> LazyHTML.attribute("content")

      economy =
        doc("/fr/pays/kenya/economie")
        |> LazyHTML.query(~s(meta[name="description"]))
        |> LazyHTML.attribute("content")

      assert overview != economy
    end

    test "the lead sentence starts with real growth, never a bare fall in dollars" do
      lead = text(doc("/en/countries/senegal"), "[data-answer]") |> String.trim()
      assert lead =~ ~r/^Senegal: growth of /
      assert lead =~ "no. "
    end
  end

  describe "structured data" do
    test "the country Dataset has what Google Dataset Search needs" do
      [dataset] = doc("/fr/pays/senegal") |> json_ld() |> Enum.filter(&(&1["@type"] == "Dataset"))
      assert dataset["description"] =~ "FMI"
      assert dataset["url"] == "http://localhost:4000/fr/pays/senegal"
      assert dataset["license"] == "https://creativecommons.org/licenses/by/4.0/"
      assert dataset["creditText"] == "Syli Atlas"
      assert dataset["creator"]["@id"] =~ "#organization"
      assert length(dataset["variableMeasured"]) >= 5
      formats = Enum.map(dataset["distribution"], & &1["encodingFormat"])
      assert "text/csv" in formats
      assert dataset["about"]["identifier"] == "SEN"
    end

    test "one dataset per source: none on tabs that repeat the IMF series" do
      refute "Dataset" in types(doc("/fr/pays/senegal/finances-et-dette"))
    end

    test "rankings are ItemLists, the method an AboutPage, the home the site" do
      assert "ItemList" in types(doc("/fr/classement/inflation"))
      assert "ItemList" in types(doc("/fr/dette"))
      assert "AboutPage" in types(doc("/fr/methode"))
      assert "WebSite" in types(doc("/fr")) and "Organization" in types(doc("/fr"))
    end
  end

  describe "thematic rankings" do
    test "each indicator has its page, title and canonical" do
      d = doc("/fr/classement/inflation")
      assert text(d, "h1") =~ "Inflation des pays africains"

      assert d |> LazyHTML.query(~s(link[rel=canonical])) |> LazyHTML.attribute("href") ==
               ["http://localhost:4000/fr/classement/inflation"]

      assert d |> LazyHTML.query(~s(link[hreflang=en])) |> LazyHTML.attribute("href") ==
               ["http://localhost:4000/en/ranking/inflation"]

      assert text(d, "#ranking-answer") =~ "Inflation, 2025"
      assert LazyHTML.query(d, ~s(meta[name=robots])) |> Enum.count() == 0
    end

    test "the bare ranking and an indicator alone send to the indicator's page" do
      assert redirected_to(get(build_conn(), "/fr/classement"), 301) == "/fr/classement/pib"

      assert redirected_to(get(build_conn(), "/fr/classement?indicator=inflation"), 301) ==
               "/fr/classement/inflation"

      assert redirected_to(get(build_conn(), "/en/ranking/croissance"), 301) ==
               "/en/ranking/growth"

      assert get(build_conn(), "/fr/classement?indicator=inflation&mode=change").status == 200
      assert_error_sent 404, fn -> get(build_conn(), "/fr/classement/atlantide") end
    end
  end

  describe "pairs" do
    test "a chosen pair is indexed, with its own title and answer" do
      d = doc("/fr/comparer/cote-d-ivoire/senegal")
      assert text(d, "title") =~ "Côte d'Ivoire ou Sénégal : PIB, croissance et dette comparés"
      assert text(d, "#pair-answer") =~ "PIB réel"
      assert LazyHTML.query(d, ~s(meta[name=robots])) |> Enum.count() == 0
    end

    test "the other order points to the pair's address; free combinations stay out" do
      d = doc("/fr/comparer/senegal/cote-d-ivoire")

      assert d |> LazyHTML.query(~s(link[rel=canonical])) |> LazyHTML.attribute("href") ==
               ["http://localhost:4000/fr/comparer/cote-d-ivoire/senegal"]

      free = doc("/fr/comparer/senegal/kenya/egypte")

      assert free |> LazyHTML.query(~s(meta[name=robots])) |> LazyHTML.attribute("content") == [
               "noindex"
             ]
    end

    test "a country links its pairs" do
      links =
        doc("/fr/pays/senegal") |> LazyHTML.query("#related a") |> LazyHTML.attribute("href")

      assert "/fr/comparer/cote-d-ivoire/senegal" in links
    end
  end

  describe "questions and about" do
    test "every question has a page answered from the data" do
      for id <- SyliAtlasWeb.Topics.questions(), locale <- ["fr", "en"] do
        path = SyliAtlasWeb.Topics.question_path(locale, id)
        d = doc(path)
        assert text(d, "#answer") != "", path
        assert "FAQPage" in types(d), path
      end

      assert text(doc("/fr/questions/pays-le-plus-riche-d-afrique"), "#answer") =~
               "Par son PIB, l'Afrique du Sud"
    end

    test "the about page says where figures come from and how to cite" do
      d = doc("/fr/a-propos")
      assert text(d, "h1") =~ "Syli Atlas"
      assert text(d, "#citer + p + p") =~ "Syli Atlas, d'après FMI"

      assert "/fr/a-propos" in (doc("/fr")
                                |> LazyHTML.query(".site-footer a")
                                |> LazyHTML.attribute("href"))
    end

    test "no link to a page that does not exist: discussions are not open" do
      links = doc("/fr/pays/senegal") |> LazyHTML.query("a") |> LazyHTML.attribute("href")
      refute Enum.any?(links, &String.ends_with?(&1, "/discussion"))
    end
  end

  describe "for crawlers" do
    test "the sitemap is an index of parts with dates; new pages are listed" do
      index = build_conn() |> get("/sitemap.xml") |> response(200)
      assert index =~ "/sitemaps/pages.xml</loc><lastmod>"
      xml = sitemaps()
      assert xml =~ "/fr/classement/inflation</loc>"
      assert xml =~ "/fr/questions/pays-le-plus-riche-d-afrique</loc>"
      assert xml =~ "/fr/comparer/cote-d-ivoire/senegal</loc>"
      assert xml =~ "/fr/a-propos</loc>"
      refute xml =~ "/fr/classement</loc>"
      assert Regex.scan(~r/<url>/, xml) |> length() == Regex.scan(~r/<lastmod>/, xml) |> length()
      assert get(build_conn(), "/sitemaps/nope.xml").status == 404
    end

    test "robots.txt lets crawlers read the open data the datasets point to" do
      txt = build_conn() |> get("/robots.txt") |> response(200)
      assert txt =~ "Allow: /api/v1/areas\nDisallow: /admin"
    end

    test "llms-full.txt gives every lead sentence with its address" do
      txt = build_conn() |> get("/llms-full.txt") |> response(200)
      assert txt =~ "Senegal: growth of"
      assert txt =~ "Sénégal : croissance de"
      assert txt =~ "http://localhost:4000/fr/pays/senegal"
      assert txt =~ "What is the richest country in Africa?"
      assert build_conn() |> get("/llms.txt") |> response(200) =~ "/llms-full.txt"
    end

    test "old addresses move permanently" do
      assert redirected_to(get(build_conn(), "/fr/pays/senegal/"), 301) == "/fr/pays/senegal"
    end

    test "the licence of the calculations is stated, sources keep theirs" do
      d = doc("/fr/methode")
      assert text(d, "#reuse ~ p") =~ "CC BY 4.0"
      assert text(d, "#reuse ~ p") =~ "MansaAPI"

      assert "https://creativecommons.org/licenses/by/4.0/" in (d
                                                                |> LazyHTML.query(
                                                                  ~s(a[rel=license])
                                                                )
                                                                |> LazyHTML.attribute("href"))

      assert "/fr/methode#reuse" in (doc("/fr")
                                     |> LazyHTML.query(".site-footer a")
                                     |> LazyHTML.attribute("href"))

      csv = build_conn() |> get("/api/v1/areas/SEN/csv") |> response(200)
      assert csv |> String.split("\n") |> hd() =~ "CC BY 4.0"
      assert build_conn() |> get("/llms.txt") |> response(200) =~ "CC BY 4.0"
    end

    test "dates are machine-readable" do
      assert LazyHTML.query(doc("/fr/regions/afrique-de-l-ouest"), ".src time[datetime]")
             |> Enum.count() >= 1
    end
  end
end
