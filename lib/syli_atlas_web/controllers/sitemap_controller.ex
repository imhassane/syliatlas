defmodule SyliAtlasWeb.SitemapController do
  @moduledoc """
  `/sitemap.xml` and `/robots.txt`. Each page is listed once, in French,
  with its English twin as an hreflang alternate. Rebuilt on every request:
  the list follows the data, so a new rating or exchange appears at once.
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.{Geo, Market, Ratings}
  alias SyliAtlas.Geo.Area
  alias SyliAtlasWeb.{Paths, Seo}

  def sitemap(conn, _params) do
    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, xml(pages()))
  end

  def robots(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, """
    User-agent: *
    Disallow: /admin
    Disallow: /api/
    Disallow: /dev/

    Sitemap: #{Seo.url("/sitemap.xml")}
    """)
  end

  @doc "Every public page as `{%{\"fr\" => path, \"en\" => path}, lastmod | nil}`."
  def pages do
    ratings = Ratings.document()
    as_of = ratings && ratings["as_of"]

    static =
      for fun <- [:home, :ranking, :regions, :method, :debt] do
        {both(&apply(Paths, fun, [&1])), nil}
      end

    areas =
      for area <- Geo.list_areas() do
        {both(&Paths.area(&1, area.kind, Area.slug(area, &1))), nil}
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

    static ++ areas ++ rating_pages ++ market_pages()
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
