defmodule SyliAtlasWeb.SearchController do
  use SyliAtlasWeb, :controller

  alias SyliAtlasWeb.{Paths, PublicData}

  plug :put_layout, false

  def index(conn, params) do
    locale = conn.assigns.locale
    q = params |> Map.get("q", "") |> to_string() |> String.trim() |> String.slice(0, 80)
    results = if q == "", do: [], else: PublicData.search(q, locale)

    case results do
      [only] when q != "" ->
        redirect(conn, to: Paths.area(locale, only["kind"], only["slug"]))

      _ ->
        render(conn, :index,
          page_title: gettext("Search"),
          seo: %{noindex: true},
          alternates: [{"fr", "/fr/recherche"}, {"en", "/en/search"}],
          q: q,
          results: results,
          countries: SyliAtlas.Geo.list_countries()
        )
    end
  end
end
