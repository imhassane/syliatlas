defmodule SyliAtlasWeb.LocalesTest do
  @moduledoc """
  The seven languages of the public site (SyliAtlas.Locales): every public
  page answers in each, with its own addresses, the html language and
  direction, hreflang twins, and the bare address `/` sends each reader to
  their language (browser first, then Cloudflare's country, then English).
  """
  use SyliAtlasWeb.ConnCase, async: false

  alias SyliAtlas.Locales
  alias SyliAtlasWeb.Paths

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    :ok
  end

  defp doc(path), do: build_conn() |> get(path) |> html_response(200) |> LazyHTML.from_document()
  defp text(doc, sel), do: doc |> LazyHTML.query(sel) |> LazyHTML.text()
  defp attr(doc, sel, name), do: doc |> LazyHTML.query(sel) |> LazyHTML.attribute(name)

  describe "pages in every language" do
    test "home, a country, its tabs, rankings, ratings, questions, glossary and about answer" do
      senegal = SyliAtlas.Geo.get_area_by_code("SEN")

      for l <- Locales.all() do
        paths =
          [
            Paths.home(l),
            Paths.area(l, senegal),
            Paths.area_tab(l, senegal, :economy),
            Paths.area_tab(l, senegal, :finances),
            SyliAtlasWeb.CountryQuestionsController.questions_path(l, senegal),
            Paths.ranking_main(l),
            Paths.regions(l),
            Paths.ratings(l),
            Paths.debt(l),
            Paths.communities(l),
            Paths.method(l),
            Paths.about(l),
            Paths.accessibility(l),
            SyliAtlasWeb.Topics.questions_path(l),
            SyliAtlasWeb.Topics.question_path(l, "richest"),
            SyliAtlasWeb.GlossaryController.index_path(l),
            SyliAtlasWeb.GlossaryController.term_path(l, "gdp"),
            SyliAtlasWeb.Topics.pair_path(l, ~w(CIV SEN)),
            Paths.search(l),
            Paths.api(l)
          ]

        for path <- paths do
          conn = build_conn() |> get(path)
          assert conn.status == 200, "#{path}: #{conn.status}"
        end
      end
    end

    test "each language has its own addresses and words" do
      assert Paths.area("es", SyliAtlas.Geo.get_area_by_code("CIV")) ==
               "/es/paises/costa-de-marfil"

      assert Paths.area("pt", SyliAtlas.Geo.get_area_by_code("CIV")) ==
               "/pt/paises/costa-do-marfim"

      assert Paths.area("ar", SyliAtlas.Geo.get_area_by_code("CIV")) ==
               "/ar/countries/cote-d-ivoire"

      es = doc("/es/paises/senegal")
      assert text(es, "h1") =~ "Senegal"
      assert attr(es, "html", "lang") == ["es"]

      zh = doc("/zh/countries/senegal")
      assert text(zh, "h1") =~ "塞内加尔"
      assert attr(zh, "html", "lang") == ["zh-Hans"]

      ar = doc("/ar/countries/senegal")
      assert attr(ar, "html", "dir") == ["rtl"]
      assert text(ar, "h1") =~ "السنغال"

      # The English slug of a country also leads, under /es, to the Spanish page.
      conn = build_conn() |> get("/es/paises/cote-d-ivoire")
      assert redirected_to(conn, 301) == "/es/paises/costa-de-marfil"
    end

    test "every page lists its twins in all languages, English as x-default" do
      d = doc("/hi/countries/senegal")

      langs =
        d |> LazyHTML.query(~s(link[rel="alternate"][hreflang])) |> LazyHTML.attribute("hreflang")

      assert Enum.sort(langs) == Enum.sort(~w(fr en es pt ar hi zh-Hans x-default))

      x_default =
        d |> LazyHTML.query(~s(link[hreflang="x-default"])) |> LazyHTML.attribute("href")

      assert [href] = x_default
      assert href =~ "/en/countries/senegal"

      menu = d |> LazyHTML.query(".lang-menu a") |> LazyHTML.attribute("href")
      assert "/pt/paises/senegal" in menu and "/fr/pays/senegal" in menu
    end

    test "the API page is translated" do
      assert text(doc("/es/api"), "main") =~ "Límites y caché"
      assert text(doc("/zh/api"), "main") =~ "共用结构"
      assert text(doc("/ar/api"), "main") =~ "المعاملات"
    end

    test "numbers follow the language" do
      assert SyliAtlasWeb.Format.number(1234.5, 1, "es") == "1.234,5"

      assert SyliAtlasWeb.Format.number(1234.5, 1, "pt") ==
               SyliAtlasWeb.Format.number(1234.5, 1, "fr")

      assert SyliAtlasWeb.Format.number(1234.5, 1, "zh") == "1,234.5"
      assert SyliAtlasWeb.Dates.day_month_year(14, 11, 2025, "zh") == "2025年11月14日"
      assert SyliAtlasWeb.Dates.day_month_year(14, 11, 2025, "es") == "14 nov. 2025"
    end

    test "the sitemaps list each page in every language" do
      body = build_conn() |> get("/sitemaps/countries.xml") |> response(200)

      assert body =~ "<loc>http://localhost:4002/es/paises/senegal</loc>" or
               body =~ "/es/paises/senegal</loc>"

      assert body =~ ~s(hreflang="zh-Hans")

      assert body =~ ~s(hreflang="x-default" href="http://localhost:4002/en/countries/senegal") or
               body =~ ~s(hreflang="x-default")
    end
  end

  describe "the bare address" do
    defp root(headers) do
      conn =
        Enum.reduce(headers, build_conn(), fn {k, v}, c -> put_req_header(c, k, v) end)
        |> get("/")

      assert conn.status == 302
      redirected_to(conn)
    end

    test "the browser's language first, when the site has it" do
      assert root([{"accept-language", "pt-BR,pt;q=0.9,en;q=0.8"}]) == "/pt"
      assert root([{"accept-language", "ar"}, {"cf-ipcountry", "SN"}]) == "/ar"
      assert root([{"accept-language", "de-DE,de;q=0.9,es;q=0.5"}]) == "/es"
    end

    test "an English browser, or none, follows the country" do
      assert root([{"accept-language", "en-US,en;q=0.9"}, {"cf-ipcountry", "SN"}]) == "/fr"
      assert root([{"cf-ipcountry", "AO"}]) == "/pt"
      assert root([{"cf-ipcountry", "EG"}]) == "/ar"
      assert root([{"cf-ipcountry", "IN"}]) == "/hi"
      assert root([{"cf-ipcountry", "CN"}]) == "/zh"
      assert root([{"cf-ipcountry", "MX"}]) == "/es"
    end

    test "English by default" do
      assert root([]) == "/en"
      assert root([{"cf-ipcountry", "NG"}]) == "/en"
      assert root([{"accept-language", "de"}, {"cf-ipcountry", "DE"}]) == "/en"
      assert root([{"accept-language", "en-GB"}, {"cf-ipcountry", "KE"}]) == "/en"
    end
  end
end
