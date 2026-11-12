defmodule SyliAtlasWeb.EmbedControllerTest do
  @moduledoc "Views framed by other sites, their security headers, oEmbed and the builder page."
  use SyliAtlasWeb.ConnCase, async: false

  alias SyliAtlasWeb.CSP

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    previous = Application.get_env(:syli_atlas, CSP)
    on_exit(fn -> Application.put_env(:syli_atlas, CSP, previous || []) end)
    :ok
  end

  defp mode(mode), do: Application.put_env(:syli_atlas, CSP, mode: mode)
  defp doc(html), do: LazyHTML.from_document(html)
  defp text(html, selector), do: html |> LazyHTML.query(selector) |> LazyHTML.text()
  defp count(html, selector), do: html |> LazyHTML.query(selector) |> Enum.count()

  describe "frame" do
    test "a chart: no header or band, the profile's chart, source and link to the profile" do
      conn = get(build_conn(), "/embed/fr/pays/cote-d-ivoire/real_gdp_index?from=2020&to=2025")
      html = conn |> html_response(200) |> doc()

      assert count(html, "header.site-header, .ticker, nav[role=tablist]") == 0
      assert text(html, "h1") =~ "PIB réel (volume), Côte d'Ivoire"
      assert count(html, "svg.chart-wide") == 1
      # Compared with its region by default.
      assert text(html, ".chart-data caption") != ""
      assert count(html, ".legend li") == 2
      assert text(html, ".embed-foot") =~ ~r/Source\s:\sFMI/u

      [href] = html |> LazyHTML.query(".embed-brand") |> LazyHTML.attribute("href")
      assert href =~ "/fr/pays/cote-d-ivoire?from=2020&to=2025"
      assert html |> LazyHTML.query(".embed-brand") |> LazyHTML.attribute("target") == ["_blank"]

      assert html |> LazyHTML.query("meta[name=robots]") |> LazyHTML.attribute("content") == [
               "noindex"
             ]
    end

    test "the key figures; options: no comparison, no title, a theme" do
      html =
        build_conn()
        |> get("/embed/en/countries/cote-d-ivoire/summary?title=0&theme=dark")
        |> html_response(200)
        |> doc()

      assert count(html, ".embed-kpis > div") == 6
      # The title is gone from sight, kept for screen readers.
      assert count(html, "h1:not(.sr-only)") == 0
      assert html |> LazyHTML.query("html") |> LazyHTML.attribute("data-theme") == ["dark"]

      html =
        build_conn()
        |> get("/embed/fr/pays/senegal/inflation?compare=0")
        |> html_response(200)
        |> doc()

      assert count(html, ".legend li") == 0
    end

    test "a newer IMF edition than the one in the code is said in the frame" do
      html =
        build_conn()
        |> get("/embed/fr/pays/cote-d-ivoire/inflation?edition=2026-04")
        |> html_response(200)

      assert html =~ "Chiffres mis à jour depuis cet article"

      refute build_conn()
             |> get("/embed/fr/pays/cote-d-ivoire/inflation?edition=2026-10")
             |> html_response(200) =~ "mis à jour depuis"
    end

    test "regions; unknown view, kind or language: 404" do
      assert build_conn()
             |> get("/embed/fr/regions/afrique-de-l-ouest/public_debt_pct_gdp")
             |> html_response(200)

      for path <- [
            "/embed/fr/pays/cote-d-ivoire/stock_prices",
            "/embed/fr/regions/cote-d-ivoire/inflation",
            "/embed/xx/pays/cote-d-ivoire/inflation"
          ] do
        assert_error_sent 404, fn -> get(build_conn(), path) end
      end
    end
  end

  describe "security headers" do
    test "frames may be framed by any site; the rest of the site may not" do
      mode(:enforce)
      conn = get(build_conn(), "/embed/fr/pays/cote-d-ivoire/inflation")

      assert get_resp_header(conn, "content-security-policy") == [CSP.embed_policy()]
      assert get_resp_header(conn, "x-frame-options") == []
      assert CSP.embed_policy() =~ "frame-ancestors *"
      assert CSP.embed_policy() =~ "script-src 'self';"
      refute CSP.embed_policy() =~ "unsafe-eval"
      assert get_resp_header(conn, "set-cookie") == []
      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]

      page = get(build_conn(), "/fr/pays/cote-d-ivoire")
      assert [policy] = get_resp_header(page, "content-security-policy")
      assert policy =~ "frame-ancestors 'self'"
      refute policy =~ "frame-ancestors *"
    end

    test "report-only: no enforced frame-ancestors on frames, the embed policy reported" do
      mode(:report_only)
      conn = get(build_conn(), "/embed/fr/pays/cote-d-ivoire/inflation")

      assert get_resp_header(conn, "content-security-policy") == []
      assert get_resp_header(conn, "content-security-policy-report-only") == [CSP.embed_policy()]

      page = get(build_conn(), "/fr/pays/cote-d-ivoire")

      assert get_resp_header(page, "content-security-policy") == [
               "base-uri 'self'; frame-ancestors 'self';"
             ]

      # Phoenix 1.8 sends no X-Frame-Options: the enforced frame-ancestors blocks.
    end

    test "a frame runs no inline script: its only script is a file of the site" do
      html = build_conn() |> get("/embed/fr/pays/cote-d-ivoire/summary") |> html_response(200)

      scripts = Regex.scan(~r{<script(\s[^>]*)?>(.*?)</script>}s, html)
      assert scripts != []

      for [_, attrs, body] <- scripts do
        assert attrs =~ ~s(src="/embed-frame.js"), "unexpected script: #{attrs}"
        assert String.trim(body) == ""
      end
    end

    test "the two scripts are served" do
      assert build_conn() |> get("/embed.js") |> response(200) =~ "syli-atlas:embed-height"
      assert build_conn() |> get("/embed-frame.js") |> response(200) =~ "postMessage"
    end
  end

  describe "accessibility" do
    test "a frame without its title still has a heading; new tabs are said" do
      html =
        build_conn()
        |> get("/embed/fr/pays/cote-d-ivoire/summary?title=0")
        |> html_response(200)
        |> doc()

      assert text(html, "h1.sr-only") =~ "Côte d'Ivoire : chiffres clés"
      assert text(html, ".embed-brand .sr-only") =~ "la fiche de la Côte d'Ivoire, nouvel onglet"
      assert text(html, ".embed-links a[href*=donnees] .sr-only") =~ "fichier CSV, nouvel onglet"
      assert html |> LazyHTML.query("html") |> LazyHTML.attribute("lang") == ["fr"]
    end

    test "a chart frame keeps its values as a table" do
      html =
        build_conn() |> get("/embed/fr/pays/senegal/inflation") |> html_response(200) |> doc()

      assert count(html, "details.chart-data table caption") == 1
      assert count(html, "svg.chart-wide[role=img][aria-label]") == 1
    end

    test "builder: every control labelled, languages named in their own language, copy announced" do
      html = build_conn() |> get("/fr/pays/cote-d-ivoire/integrer") |> html_response(200) |> doc()

      assert text(html, "h1") =~ "Intégrer les chiffres de la Côte d'Ivoire"
      assert count(html, "#embed-form select") == count(html, "#embed-form label.field select")

      assert count(html, "#embed-form input[type=radio]") ==
               count(html, "#embed-form fieldset label input[type=radio]")

      assert count(html, "select[name=lang] option[lang]") == length(SyliAtlas.Locales.all())

      assert html |> LazyHTML.query("#embed-code") |> LazyHTML.attribute("aria-describedby") == [
               "embed-code-hint"
             ]

      assert count(html, "[data-copy-status][role=status]") == 1
      assert count(html, "iframe.embed-preview[title]") == 1
    end

    test "the Data menu closes with Escape like the site's other menus; files are named as files" do
      html = build_conn() |> get("/fr/pays/cote-d-ivoire") |> html_response(200) |> doc()
      assert count(html, "details#data-menu[data-nav-menu] > summary") == 1
      assert text(html, "#data-csv .sr-only") =~ "fichier"
    end

    test "the language menu is named by its visible text (WCAG 2.5.3)" do
      html = build_conn() |> get("/fr") |> html_response(200) |> doc()
      assert html |> LazyHTML.query(".lang-menu summary[aria-label]") |> Enum.count() == 0
      assert text(html, "#lang-header summary") =~ ~r/Langue\s:\s+Français/u
    end
  end

  describe "oEmbed" do
    test "a profile address gives the key figures; a frame address its own view" do
      url = SyliAtlasWeb.Endpoint.url() <> "/fr/pays/cote-d-ivoire/economie?from=2020&to=2025"

      assert %{"type" => "rich", "version" => "1.0", "html" => html, "height" => 320} =
               build_conn() |> get("/oembed", url: url) |> json_response(200)

      assert html =~ ~s(/embed/fr/pays/cote-d-ivoire/summary?)
      assert html =~ "from=2020"
      assert html =~ "embed.js"

      url = SyliAtlasWeb.Endpoint.url() <> "/embed/en/countries/senegal/inflation?compare=0"

      assert %{"html" => html, "width" => 500} =
               build_conn() |> get("/oembed", url: url, maxwidth: "500") |> json_response(200)

      assert html =~ "/embed/en/countries/senegal/inflation?compare=0"
    end

    test "other sites, unknown pages and XML are refused" do
      assert build_conn()
             |> get("/oembed", url: "https://example.com/fr/pays/senegal")
             |> json_response(404)

      assert build_conn() |> get("/oembed", url: "/fr/pays/atlantide") |> json_response(404)

      assert build_conn()
             |> get("/oembed", url: "/fr/pays/senegal", format: "xml")
             |> json_response(501)

      assert build_conn() |> get("/oembed") |> json_response(400)
    end

    test "profiles announce it" do
      html = build_conn() |> get("/fr/pays/cote-d-ivoire") |> html_response(200) |> doc()

      [href] =
        html
        |> LazyHTML.query(~s(link[type="application/json+oembed"]))
        |> LazyHTML.attribute("href")

      assert href =~
               "/oembed?url=" <>
                 URI.encode_www_form(SyliAtlasWeb.Endpoint.url() <> "/fr/pays/cote-d-ivoire")
    end
  end

  describe "builder page" do
    test "preview and code follow the form; the code names the edition" do
      html =
        build_conn()
        |> get(
          "/fr/pays/cote-d-ivoire/integrer?view=inflation&from=2018&to=2026&theme=dark&compare=0&title=1"
        )
        |> html_response(200)
        |> doc()

      [src] = html |> LazyHTML.query("iframe.embed-preview") |> LazyHTML.attribute("src")

      assert src =~
               "/embed/fr/pays/cote-d-ivoire/inflation?from=2018&to=2026&edition=2026-10&compare=0&theme=dark"

      code = text(html, "#embed-code")
      assert code =~ ~s(<iframe src=")
      assert code =~ "edition=2026-10"
      assert code =~ ~s(title="Inflation, Côte d&#39;Ivoire) or code =~ "Inflation, Côte d"
      assert code =~ "/embed.js"

      assert html |> LazyHTML.query("meta[name=robots]") |> LazyHTML.attribute("content") == [
               "noindex"
             ]
    end

    test "another language for the frame; regions; the English address" do
      html = build_conn() |> get("/fr/pays/senegal/integrer?lang=en") |> html_response(200)
      assert html =~ "/embed/en/countries/senegal/real_gdp_index"

      assert build_conn() |> get("/fr/regions/afrique-de-l-ouest/integrer") |> html_response(200)
      assert build_conn() |> get("/en/countries/senegal/embed") |> html_response(200)
    end
  end
end
