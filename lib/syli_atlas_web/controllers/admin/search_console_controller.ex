defmodule SyliAtlasWeb.Admin.SearchConsoleController do
  @moduledoc """
  Admin: Google Search Console, imported each morning (`SyliAtlas.SearchConsole`),
  and the pages of the other languages to have read by a native speaker.
  """
  use SyliAtlasWeb, :controller
  alias SyliAtlas.SearchConsole

  @periods [7, 28, 90]

  def index(conn, params) do
    days = period(params["jours"])

    render(conn, :index,
      page_title: "Admin · Recherche Google",
      configured: SearchConsole.configured?(),
      site: SearchConsole.site(),
      days: days,
      periods: @periods,
      totals: SearchConsole.totals(days),
      daily: SearchConsole.daily(days),
      devices: SearchConsole.top("device", days, 5),
      sections: SearchConsole.by_section(days) |> Enum.take(20),
      opportunities: SearchConsole.opportunities(days),
      queries: SearchConsole.top("query", days, 30),
      countries: SearchConsole.top("country", days, 10)
    )
  end

  def import(conn, _params) do
    if SearchConsole.configured?() do
      Oban.insert!(SyliAtlas.Workers.SearchConsoleWorker.new(%{"days" => 28}))

      conn
      |> put_flash(:info, "Import des 28 derniers jours demandé.")
      |> redirect(to: ~p"/admin/recherche-google")
    else
      conn
      |> put_flash(:error, "Clé du compte de service absente.")
      |> redirect(to: ~p"/admin/recherche-google")
    end
  end

  def translations(conn, params) do
    days = period(params["jours"])
    pages = SearchConsole.pages_to_review(days)
    lang = if params["langue"] in ~w(es pt ar hi zh), do: params["langue"]

    render(conn, :translations,
      page_title: "Admin · Traductions",
      configured: SearchConsole.configured?(),
      days: days,
      lang: lang,
      by_lang: summary(pages),
      pages: pages |> Enum.filter(&(is_nil(lang) or &1.lang == lang)) |> Enum.take(200)
    )
  end

  def review(conn, %{"path" => path, "reviewer" => reviewer}) do
    if String.starts_with?(path, "/") and String.trim(reviewer) != "" do
      SearchConsole.review!(path, reviewer)
      conn |> put_flash(:info, "Page marquée relue.") |> redirect(to: ~p"/admin/traductions")
    else
      conn
      |> put_flash(:error, "Nom du relecteur manquant.")
      |> redirect(to: ~p"/admin/traductions")
    end
  end

  defp summary(pages) do
    for lang <- ~w(pt es ar zh hi) do
      rows = Enum.filter(pages, &(&1.lang == lang))
      impressions = rows |> Enum.map(& &1.impressions) |> Enum.sum()

      %{
        lang: lang,
        pages: length(rows),
        impressions: impressions,
        reviewed: Enum.count(rows, & &1.review),
        position:
          if(impressions > 0,
            do:
              (rows |> Enum.map(&((&1.position || 0) * &1.impressions)) |> Enum.sum()) /
                impressions
          )
      }
    end
  end

  defp period(value) do
    case Integer.parse(value || "") do
      {n, ""} when n in @periods -> n
      _ -> 28
    end
  end
end
