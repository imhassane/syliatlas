defmodule SyliAtlasWeb.TradeRankingHTML do
  use SyliAtlasWeb, :html

  alias SyliAtlas.Trade
  alias SyliAtlasWeb.{TradeRankingController, TradeTopics}

  embed_templates "trade_ranking_html/*"

  defdelegate pct(v, locale), to: TradeRankingController
  defdelegate value_label(id), to: TradeRankingController
  defdelegate question(id), to: TradeRankingController

  def usd(v, locale), do: SyliAtlasWeb.WorldBankComponents.usd(v, locale)

  @doc "Link to the ranking with one option changed, defaults dropped."
  def list_href(locale, id, kept, changes) do
    params =
      kept
      |> Map.merge(changes)
      |> Enum.reject(fn {k, v} ->
        v in [nil, ""] or {k, v} in [{"sort", "value"}] or
          (k == "dir" and v == default_dir(Map.merge(kept, changes)["sort"]))
      end)

    TradeTopics.ranking_path(locale, id) <>
      case params do
        [] -> ""
        params -> "?" <> URI.encode_query(params)
      end
  end

  defp default_dir("name"), do: "asc"
  defp default_dir(_), do: "desc"

  @doc "Href of a column heading: the other direction when it is the current sort."
  def sort_href(locale, id, kept, key, sort, dir) do
    next =
      cond do
        key != sort -> default_dir(key)
        dir == "asc" -> "desc"
        true -> "asc"
      end

    list_href(locale, id, kept, %{"sort" => key, "dir" => next}) <> "#ranking-table"
  end

  def aria_sort(key, sort, dir) when key == sort,
    do: if(dir == "asc", do: "ascending", else: "descending")

  def aria_sort(_, _, _), do: "none"

  def arrow(key, sort, dir) when key == sort, do: if(dir == "asc", do: " ↑", else: " ↓")
  def arrow(_, _, _), do: ""

  def product(_doc, nil, _locale), do: "—"
  def product(doc, code, locale), do: Trade.heading(doc, code, locale)

  def partner(doc, code, locale), do: SyliAtlasWeb.TradeComponents.partner(doc, code, locale)

  @doc "Width of a bar, % of 100."
  def width(nil), do: 0
  def width(v), do: v |> max(0) |> min(100) |> Float.round(1)

  @doc "Search text of a row: names without accents, code."
  def search_text(row),
    do: SyliAtlas.Geo.Area.normalize(row.name) <> " " <> String.downcase(row.code)

  def count_text(rows, q) do
    if q == "",
      do: ngettext("%{count} country", "%{count} countries", length(rows)),
      else:
        ngettext("%{count} result for « %{q} »", "%{count} results for « %{q} »", length(rows),
          q: q
        )
  end

  def count_template(n),
    do: ngettext("%{count} result for « %{q} »", "%{count} results for « %{q} »", n, q: "__Q__")
end
