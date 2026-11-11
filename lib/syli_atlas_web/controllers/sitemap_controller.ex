defmodule SyliAtlasWeb.SitemapController do
  @moduledoc """
  `/sitemap.xml` and `/robots.txt`. Each page is listed in every language
  of the site, each address with all its twins as hreflang alternates
  (x-default: English). Rebuilt on every request:
  the list follows the data, so a new rating or exchange appears at once.
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.{Geo, Market, Ratings}
  alias SyliAtlasWeb.{Paths, Seo}

  @parts ~w(pages countries ratings markets securities)

  @doc """
  `/sitemap.xml`: an index of one sitemap per kind of page, each with the
  date its data last changed (`lastmod`). Search engines read the date of a
  part before its pages.
  """
  def sitemap(conn, _params) do
    parts = groups()

    entries =
      for name <- @parts, pages = parts[name] || [], pages != [] do
        lastmod =
          pages |> Enum.map(&elem(&1, 1)) |> Enum.reject(&is_nil/1) |> Enum.max(fn -> nil end)

        [
          "<sitemap><loc>",
          esc(Seo.url("/sitemaps/#{name}.xml")),
          "</loc>",
          if(lastmod, do: ["<lastmod>", esc(lastmod), "</lastmod>"], else: []),
          "</sitemap>\n"
        ]
      end

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(
      200,
      IO.iodata_to_binary([
        ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
        ~s(<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n),
        entries,
        "</sitemapindex>\n"
      ])
    )
  end

  @doc "`/sitemaps/<part>.xml`: the pages of one kind."
  def part(conn, %{"part" => file}) do
    name = String.trim_trailing(file, ".xml")

    if name in @parts and String.ends_with?(file, ".xml") do
      conn
      |> put_resp_content_type("application/xml")
      |> send_resp(200, xml(groups()[name] || []))
    else
      conn |> put_resp_content_type("text/plain") |> send_resp(404, "Not found")
    end
  end

  @doc """
  `/llms.txt`: what the site holds and where, for language models and
  answer engines (https://llmstxt.org). Plain Markdown, built from the data.
  """
  def llms(conn, _params) do
    conn
    |> put_resp_content_type("text/markdown")
    |> send_resp(200, llms_txt())
  end

  defp llms_txt do
    edition = SyliAtlas.Sources.published_edition("imf_weo")
    countries = Geo.list_countries() |> Enum.sort_by(& &1.name_en)

    country_lines =
      for c <- countries do
        "- [#{c.name_en}](#{Seo.url(Paths.area("en", c))}): GDP, growth, inflation, debt, trade, society, rating · " <>
          "[FR](#{Seo.url(Paths.area("fr", c))}) · [JSON](#{Seo.url("/api/v1/areas/" <> c.code)})"
      end

    community_lines =
      for c <- SyliAtlas.Economy.Communities.all() do
        "- [#{c.short["en"]}, #{c.name["en"]}](#{Seo.url(Paths.community("en", c.slug["en"]))}): members, totals"
      end

    """
    # Syli Atlas

    > African economies in verifiable figures, in French and English. Every figure comes from a
    > named public source (IMF, World Bank, CEPII BACI, rating agencies, MansaAPI for markets),
    > with its edition and terms on the method page. Non-commercial, free, no account needed.

    Licence: what Syli Atlas computes and writes (totals, ranks, changes, sentences, images) is CC BY 4.0
    (#{Seo.license_url()}): reuse freely with credit to Syli Atlas and the page address. Source figures keep
    their source's terms; stock prices (MansaAPI) are not redistributable.

    IMF edition: #{(edition && edition.label) || "n/a"}. Country profiles have one page per theme:
    overview, economy, finances and debt, trade, society, markets. Information, not investment advice.

    ## Main pages

    - [Ranking of the 54 countries](#{Seo.url(Paths.ranking_main("en"))})
    - [Debt of African countries](#{Seo.url(Paths.debt("en"))})
    - [Sovereign credit ratings](#{Seo.url(Paths.ratings("en"))})
    - [Economic communities](#{Seo.url(Paths.communities("en"))})
    - [Regions of Africa](#{Seo.url(Paths.regions("en"))})
    - [Method and sources](#{Seo.url(Paths.method("en"))}): sources, editions, licences, calculations

    ## Rankings and questions

    #{Enum.map_join(SyliAtlasWeb.Topics.ranking_indicators(), "\n", fn i -> "- [#{Gettext.with_locale(SyliAtlasWeb.Gettext, "en", fn -> SyliAtlasWeb.Topics.ranking_title(i, year()) end)}](#{Seo.url(SyliAtlasWeb.Topics.ranking_path("en", i))})" end)}
    #{Enum.map_join(SyliAtlasWeb.Topics.questions(), "\n", fn q -> "- [#{Gettext.with_locale(SyliAtlasWeb.Gettext, "en", fn -> SyliAtlasWeb.Topics.question_text(q) end)}](#{Seo.url(SyliAtlasWeb.Topics.question_path("en", q))})" end)}

    ## En français

    Le site existe aussi en français : [accueil](#{Seo.url("/fr")}), [classements](#{Seo.url(SyliAtlasWeb.Topics.ranking_path("fr", "gdp_usd_bn"))}), [questions](#{Seo.url(SyliAtlasWeb.Topics.questions_path("fr"))}), [notations souveraines](#{Seo.url(Paths.ratings("fr"))}), [dette](#{Seo.url(Paths.debt("fr"))}), [méthode et sources](#{Seo.url(Paths.method("fr"))}). Chaque fiche pays a son adresse française (lien FR ci-dessous).
    Also in Spanish, Portuguese, Arabic, Hindi and Chinese: [Español](#{Seo.url("/es")}), [Português](#{Seo.url("/pt")}), [العربية](#{Seo.url("/ar")}), [हिन्दी](#{Seo.url("/hi")}), [中文](#{Seo.url("/zh")}). Every page has its address in each language (hreflang alternates in the sitemap).

    ## Data

    - [Every lead sentence in plain text, French and English](#{Seo.url("/llms-full.txt")})
    - [About, how to cite](#{Seo.url(Paths.about("en"))})
    - [Public API documentation](#{Seo.url(Paths.api("en"))}): routes, parameters, examples, limits, server time
    - [Public JSON API, list of areas](#{Seo.url("/api/v1/areas")})
    - [OpenAPI description of the API](#{Seo.url("/api/v1/openapi.json")})
    - [Indicators: units and definitions](#{Seo.url("/api/v1/indicators")})
    - [Sitemap](#{Seo.url("/sitemap.xml")})

    ## Economic communities

    #{Enum.join(community_lines, "\n")}

    ## Countries

    #{Enum.join(country_lines, "\n")}
    """
  end

  defp year, do: elem(SyliAtlas.Profiles.Builder.default_period(), 1)

  @doc """
  `/llms-full.txt`: the lead sentence of every profile, region, community,
  rating and question, in English and French, with its address: what an
  answer engine needs to quote a figure with its source and date.
  """
  def llms_full(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, llms_full_txt())
  end

  defp llms_full_txt do
    {from, to} = SyliAtlas.Profiles.Builder.default_period()
    edition = SyliAtlas.Sources.published_edition("imf_weo")

    areas =
      for area <- Geo.list_areas(), area.kind in ["country", "region", "continent"] do
        lines =
          for locale <- ["en", "fr"],
              data = SyliAtlasWeb.PublicData.area(area.code, from, to),
              data != nil do
            Gettext.with_locale(SyliAtlasWeb.Gettext, locale, fn ->
              name = SyliAtlas.Geo.Area.name(area, locale)

              "#{SyliAtlasWeb.AreaController.answer(name, data, from, to, locale)} #{Seo.url(Paths.area(locale, area))}"
            end)
          end

        ["## ", area.name_en, "\n\n", Enum.join(lines, "\n"), "\n\n"]
      end

    questions =
      for q <- SyliAtlasWeb.Topics.questions(), locale <- ["en", "fr"] do
        Gettext.with_locale(SyliAtlasWeb.Gettext, locale, fn ->
          case SyliAtlasWeb.QuestionsController.answer(q, locale) do
            nil ->
              []

            a ->
              [
                "- ",
                SyliAtlasWeb.Topics.question_text(q),
                " ",
                a.text,
                " ",
                Seo.url(SyliAtlasWeb.Topics.question_path(locale, q)),
                "\n"
              ]
          end
        end)
      end

    IO.iodata_to_binary([
      "# Syli Atlas: every lead sentence\n\n",
      "Source of the economic figures: IMF, #{(edition && edition.label) || "World Economic Outlook"}. ",
      "#{to} is an estimate, later years projections. Changes are measured from #{from}. ",
      "Cite: Syli Atlas, from IMF, with the page address and the date.\n\n",
      "## Questions\n\n",
      questions,
      "\n",
      areas
    ])
  end

  def robots(conn, _params) do
    if SyliAtlasWeb.Plugs.CanonicalHost.noindex?() do
      # Development copy of the site: nothing to index, no sitemap.
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(200, "User-agent: *\nDisallow: /\n")
    else
      public_robots(conn)
    end
  end

  defp public_robots(conn) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, """
    User-agent: *
    Allow: /api/v1/areas
    Disallow: /admin
    Disallow: /api/
    Disallow: /dev/
    Disallow: /account
    Disallow: /unsubscribe/

    Sitemap: #{Seo.url("/sitemap.xml")}
    """)
  end

  @doc "Every public page as `{%{\"fr\" => path, \"en\" => path}, lastmod | nil}`."
  def pages, do: groups() |> Map.values() |> Enum.concat()

  @doc "The public pages by sitemap part."
  def groups do
    ratings = Ratings.document()
    as_of = ratings && ratings["as_of"]
    imf = imf_date()

    static =
      for fun <- [:home, :regions, :method, :accessibility, :debt, :communities, :api] do
        {both(&apply(Paths, fun, [&1])), imf}
      end ++
        for(p <- SyliAtlasWeb.Topics.sitemap_pages(), do: {p, imf})

    # A country is listed once per tab that has data: each tab has its
    # own canonical URL, title and answer.
    areas =
      for area <- Geo.list_areas(), tab <- SyliAtlasWeb.AreaController.tabs_for(area) do
        {both(&Paths.area_tab(&1, area, tab)), imf}
      end ++
        for area <- Geo.list_countries() do
          {both(&SyliAtlasWeb.CountryQuestionsController.questions_path(&1, area)), imf}
        end

    communities =
      for c <- SyliAtlas.Economy.Communities.all() do
        {both(&Paths.community(&1, c.slug[&1])), SyliAtlas.Economy.Communities.as_of() || imf}
      end

    # Countries without any rating have a page, out of the index (noindex).
    rating_pages =
      if ratings do
        [{both(&Paths.ratings/1), as_of}] ++
          for code <- ratings["ranking"], entry = ratings["countries"][code] do
            {both(&Paths.rating(&1, entry["slug"][&1])), as_of}
          end
      else
        []
      end

    {markets, securities} = market_pages()

    %{
      "pages" => static ++ communities,
      "countries" => areas,
      "ratings" => rating_pages,
      "markets" => markets,
      "securities" => securities
    }
  end

  defp imf_date do
    case SyliAtlas.Sources.published_edition("imf_weo") do
      %{fetched_at: %DateTime{} = at} -> at |> DateTime.to_date() |> Date.to_iso8601()
      _ -> nil
    end
  end

  defp market_pages do
    with true <- Market.public?(), %{"exchanges" => exchanges} = overview <- Market.overview() do
      day = overview["as_of"] && String.slice(overview["as_of"], 0, 10)

      markets =
        [{both(&Paths.markets/1), day}, {both(&Paths.etfs/1), day}] ++
          for x <- exchanges, code = x["exchange"]["code"] do
            {both(&Paths.exchange(&1, code)), x["index"]["date"] || day}
          end

      securities =
        for x <- exchanges,
            code = x["exchange"]["code"],
            doc = Market.exchange(code),
            row <- (doc && doc["securities"]) || [],
            is_binary(row["ticker"]) do
          {both(&Paths.security(&1, code, row["ticker"])), row["trade_date"] || day}
        end

      {markets, securities}
    else
      _ -> {[], []}
    end
  end

  defp both(fun), do: SyliAtlas.Locales.each(fn l -> fun.(l) end)

  defp xml(pages) do
    urls =
      Enum.map(pages, fn {paths, lastmod} ->
        links =
          for {lang, path} <-
                for(
                  l <- SyliAtlas.Locales.all(),
                  paths[l],
                  do: {SyliAtlas.Locales.tag(l), paths[l]}
                ) ++
                  [{"x-default", paths["en"] || paths["fr"]}] do
            [
              ~s(<xhtml:link rel="alternate" hreflang="),
              lang,
              ~s(" href="),
              esc(Seo.url(path)),
              ~s("/>)
            ]
          end

        modified = if(lastmod, do: ["<lastmod>", esc(lastmod), "</lastmod>"], else: [])

        for l <- SyliAtlas.Locales.all(), paths[l] do
          ["<url><loc>", esc(Seo.url(paths[l])), "</loc>", modified, links, "</url>\n"]
        end
      end)

    IO.iodata_to_binary([
      ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
      ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">\n),
      urls,
      "</urlset>\n"
    ])
  end

  defp esc(s), do: s |> Plug.HTML.html_escape() |> IO.iodata_to_binary()
end
