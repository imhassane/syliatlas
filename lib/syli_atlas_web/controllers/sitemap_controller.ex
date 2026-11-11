defmodule SyliAtlasWeb.SitemapController do
  @moduledoc """
  `/sitemap.xml` and `/robots.txt`. Each page is listed once, in French,
  with its English twin as an hreflang alternate. Rebuilt on every request:
  the list follows the data, so a new rating or exchange appears at once.
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.{Geo, Market, Ratings}
  alias SyliAtlasWeb.{Paths, Seo}

  def sitemap(conn, _params) do
    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, xml(pages()))
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

    IMF edition: #{(edition && edition.label) || "n/a"}. Country profiles have one page per theme:
    overview, economy, finances and debt, trade, society, markets. Information, not investment advice.

    ## Main pages

    - [Ranking of the 54 countries](#{Seo.url(Paths.ranking("en"))})
    - [Debt of African countries](#{Seo.url(Paths.debt("en"))})
    - [Sovereign credit ratings](#{Seo.url(Paths.ratings("en"))})
    - [Economic communities](#{Seo.url(Paths.communities("en"))})
    - [Regions of Africa](#{Seo.url(Paths.regions("en"))})
    - [Method and sources](#{Seo.url(Paths.method("en"))}): sources, editions, licences, calculations

    ## Data

    - [Public JSON API, list of areas](#{Seo.url("/api/v1/areas")})
    - [Search API](#{Seo.url("/api/v1/search?q=debt+senegal&locale=en")})
    - [Sitemap](#{Seo.url("/sitemap.xml")})

    ## Economic communities

    #{Enum.join(community_lines, "\n")}

    ## Countries

    #{Enum.join(country_lines, "\n")}
    """
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
    Disallow: /admin
    Disallow: /api/
    Disallow: /dev/
    Disallow: /account
    Disallow: /unsubscribe/

    Sitemap: #{Seo.url("/sitemap.xml")}
    """)
  end

  @doc "Every public page as `{%{\"fr\" => path, \"en\" => path}, lastmod | nil}`."
  def pages do
    ratings = Ratings.document()
    as_of = ratings && ratings["as_of"]

    static =
      for fun <- [:home, :ranking, :regions, :method, :accessibility, :debt, :communities] do
        {both(&apply(Paths, fun, [&1])), nil}
      end

    # A country is listed once per tab that has data: each tab has its
    # own canonical URL, title and answer.
    areas =
      for area <- Geo.list_areas(), tab <- SyliAtlasWeb.AreaController.tabs_for(area) do
        {both(&Paths.area_tab(&1, area, tab)), nil}
      end

    communities =
      for c <- SyliAtlas.Economy.Communities.all() do
        {both(&Paths.community(&1, c.slug[&1])), SyliAtlas.Economy.Communities.as_of()}
      end

    rating_pages =
      if ratings do
        [{both(&Paths.ratings/1), as_of}] ++
          for code <- ratings["ranking"], entry = ratings["countries"][code] do
            {both(&Paths.rating(&1, entry["slug"][&1])), as_of}
          end
      else
        []
      end

    static ++ areas ++ communities ++ rating_pages ++ market_pages()
  end

  defp market_pages do
    with true <- Market.public?(), %{"exchanges" => exchanges} <- Market.overview() do
      [{both(&Paths.markets/1), nil}, {both(&Paths.etfs/1), nil}] ++
        for x <- exchanges, code = x["exchange"]["code"] do
          {both(&Paths.exchange(&1, code)), nil}
        end
    else
      _ -> []
    end
  end

  defp both(fun), do: %{"fr" => fun.("fr"), "en" => fun.("en")}

  defp xml(pages) do
    urls =
      Enum.map(pages, fn {paths, lastmod} ->
        [
          "<url><loc>",
          esc(Seo.url(paths["fr"])),
          "</loc>",
          if(lastmod, do: ["<lastmod>", esc(lastmod), "</lastmod>"], else: []),
          for {lang, path} <- [
                {"fr", paths["fr"]},
                {"en", paths["en"]},
                {"x-default", paths["fr"]}
              ] do
            [
              ~s(<xhtml:link rel="alternate" hreflang="),
              lang,
              ~s(" href="),
              esc(Seo.url(path)),
              ~s("/>)
            ]
          end,
          "</url>\n"
        ]
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
