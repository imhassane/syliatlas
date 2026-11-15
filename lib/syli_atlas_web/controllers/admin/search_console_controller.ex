defmodule SyliAtlasWeb.Admin.SearchConsoleController do
  @moduledoc """
  Admin: Google Search Console, imported each morning (`SyliAtlas.SearchConsole`),
  and the pages of the other languages to have read by a native speaker.
  """
  use SyliAtlasWeb, :controller
  alias SyliAtlas.SearchConsole

  @periods [7, 28, 90]

  @tabs ~w(requetes pages langues appareils pays)

  def index(conn, params) do
    days = period(params["jours"])
    tab = if params["onglet"] in @tabs, do: params["onglet"], else: "requetes"
    measure = if params["mesure"] == "rang", do: "rang", else: "volume"
    totals = SearchConsole.totals(days)
    bands = SearchConsole.bands(days)

    render(conn, :index,
      page_title: "Admin · Recherche Google",
      configured: SearchConsole.configured?(),
      site: SearchConsole.site(),
      last_day: SearchConsole.last_day(),
      last_import: SearchConsole.last_import(),
      days: days,
      periods: @periods,
      tab: tab,
      tabs: @tabs,
      measure: measure,
      totals: totals,
      bands: bands,
      first_page:
        bands |> Enum.filter(&(&1.band in [:top3, :page1])) |> Enum.map(& &1.pages) |> Enum.sum(),
      daily: daily(SearchConsole.daily(days), days),
      opportunities: SearchConsole.opportunities(days, 6),
      rows: rows(tab, days)
    )
  end

  # Over 60 days, one bar a week (from Monday).
  defp daily(days_rows, days) when days > 60 do
    days_rows
    |> Enum.group_by(&Date.beginning_of_week(&1.date))
    |> Enum.sort_by(&elem(&1, 0), Date)
    |> Enum.map(fn {week, rows} ->
      imp = rows |> Enum.map(& &1.impressions) |> Enum.sum()

      %{
        date: week,
        week: true,
        clicks: rows |> Enum.map(& &1.clicks) |> Enum.sum(),
        impressions: imp,
        position:
          if(imp > 0,
            do: (rows |> Enum.map(&((&1.position || 0) * &1.impressions)) |> Enum.sum()) / imp
          )
      }
    end)
  end

  defp daily(rows, _days), do: Enum.map(rows, &Map.put(&1, :week, false))

  defp rows("requetes", days), do: SearchConsole.top("query", days, 200)
  defp rows("pages", days), do: SearchConsole.top("page", days, 200)
  defp rows("appareils", days), do: SearchConsole.top("device", days, 10)
  defp rows("pays", days), do: SearchConsole.top("country", days, 60)

  defp rows("langues", days) do
    SearchConsole.by_section(days)
    |> Enum.group_by(& &1.lang)
    |> Enum.map(fn {lang, rs} ->
      imp = rs |> Enum.map(& &1.impressions) |> Enum.sum()

      %{
        key: lang,
        clicks: rs |> Enum.map(& &1.clicks) |> Enum.sum(),
        impressions: imp,
        position:
          if(imp > 0,
            do: (rs |> Enum.map(&((&1.position || 0) * &1.impressions)) |> Enum.sum()) / imp
          )
      }
    end)
    |> Enum.sort_by(&(-&1.impressions))
  end

  def mark(conn, %{"query" => query} = params) do
    done? = params["done"] == "1"
    by = (conn.assigns[:current_user] && conn.assigns.current_user.email) || "admin"
    SearchConsole.mark!(query, by, done?)

    conn
    |> put_flash(:info, if(done?, do: "Marquée traitée.", else: "Rouverte."))
    |> redirect(to: ~p"/admin/recherche-google" <> "#gsc-todo")
  end

  def import(conn, _params) do
    if SearchConsole.configured?() do
      Oban.insert!(SyliAtlas.Workers.SearchConsoleWorker.new(%{"days" => 28}))

      conn
      |> put_flash(
        :info,
        "Import des 28 derniers jours demandé : l'état s'affiche en haut de la page."
      )
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
