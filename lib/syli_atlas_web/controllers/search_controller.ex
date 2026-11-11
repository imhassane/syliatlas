defmodule SyliAtlasWeb.SearchController do
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Search.Miss
  alias SyliAtlasWeb.Search

  plug :put_layout, false

  def index(conn, params) do
    locale = conn.assigns.locale
    q = params |> Map.get("q", "") |> to_string() |> String.trim() |> String.slice(0, 80)
    search = if q == "", do: nil, else: Search.run(q, locale)

    if search && Search.miss?(search), do: Miss.record(search["query"], locale)

    case search do
      # One name typed in full: straight to the page.
      %{"exact" => true, "results" => [first | _]} ->
        redirect(conn, to: first["path"])

      %{"results" => [only]} ->
        redirect(conn, to: only["path"])

      _ ->
        render(conn, :index,
          page_title: gettext("Search"),
          seo: %{noindex: true},
          alternates: [{"fr", "/fr/recherche"}, {"en", "/en/search"}],
          q: q,
          search: search,
          countries: SyliAtlas.Geo.list_countries()
        )
    end
  end
end
