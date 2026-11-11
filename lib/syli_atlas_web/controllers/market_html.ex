defmodule SyliAtlasWeb.MarketHTML do
  use SyliAtlasWeb, :html
  import SyliAtlasWeb.MarketComponents
  alias SyliAtlasWeb.{Pagination, ProfileComponents}

  embed_templates "market_html/*"

  def region_tab(nil), do: gettext("All")
  def region_tab("west_africa"), do: gettext("West")
  def region_tab("north_africa"), do: gettext("North")
  def region_tab("central_africa"), do: gettext("Central")
  def region_tab("east_africa"), do: gettext("East")
  def region_tab("southern_africa"), do: gettext("Southern")

  @doc "The source shown for an exchange: its index's, else its rank 1 source."
  def source_name(%{"index" => %{"source" => code}}) when is_binary(code),
    do: SyliAtlas.Market.Catalog.name(code)

  def source_name(%{"sources" => [s | _]}), do: s["name"]
  def source_name(_), do: "—"

  @doc "Link to the list with one parameter changed (the others kept)."
  def list_href(locale, kept, key, value) do
    params = Map.put(kept, key, value)
    params = if key == "sort", do: Map.put(params, "dir", nil), else: params
    Pagination.href(Paths.markets(locale), params, "page", 1)
  end

  @doc "Link sorting the list by a column: a second click reverses the order."
  def sort_href(locale, kept, column, sort, dir) do
    params =
      if column == sort do
        Map.put(kept, "dir", if(dir == "asc", do: "desc", else: "asc"))
      else
        kept |> Map.put("sort", column) |> Map.put("dir", nil)
      end

    params =
      if params["sort"] == "listed" and params["dir"] in [nil, "desc"],
        do: Map.drop(params, ["sort", "dir"]),
        else: params

    Pagination.href(Paths.markets(locale), params, "page", 1, "exchanges")
  end

  def aria_sort(column, sort, dir) do
    cond do
      column != sort -> "none"
      dir == "asc" -> "ascending"
      true -> "descending"
    end
  end

  def arrow(column, sort, dir) do
    cond do
      column != sort -> ""
      dir == "asc" -> "↑"
      true -> "↓"
    end
  end

  def count_text(rows, q, locale) do
    _ = locale
    n = length(rows)

    if q != "",
      do: ngettext("%{count} result for « %{q} »", "%{count} results for « %{q} »", n, q: q),
      else: ngettext("%{count} exchange", "%{count} exchanges", n)
  end

  @doc "The count line for the live search: the script puts the count first and the query in __Q__."
  def count_template(n) do
    ngettext("%{count} result for « %{q} »", "%{count} results for « %{q} »", n, q: "__Q__")
  end

  def security_flag(row) do
    cond do
      row["flags"]["held"] -> {:warn, gettext("on hold, to check")}
      row["flags"]["stale"] -> {:warn, gettext("old")}
      row["flags"]["no_trade"] -> {:neutral, gettext("no trade")}
      true -> nil
    end
  end

  def issue_text(%{"rule" => "index_missing"}, _locale),
    do: gettext("index not provided by the source")

  def issue_text(%{"rule" => "stale", "data" => %{"as_of" => d}}, locale),
    do: gettext("no session received since %{date}", date: day(d, locale))

  def issue_text(%{"rule" => "suspect_change"}, _locale),
    do: gettext("daily change identical to the change since 1 January")

  def issue_text(%{"detail" => d}, _locale), do: d

  def country_name(nil, _locale), do: nil
  def country_name(c, locale), do: SyliAtlas.Locales.pick(c["name"], locale)

  def country_href(c, locale),
    do: Paths.area(locale, "country", SyliAtlas.Locales.pick(c["slug"], locale))

  def etf_tag(%{"name" => name}) do
    n = String.downcase(name || "")

    cond do
      String.contains?(n, "gold") -> gettext("physical gold")
      String.contains?(n, "bond") -> gettext("government bonds")
      String.contains?(n, "halal") -> gettext("sharia")
      true -> nil
    end
  end
end
