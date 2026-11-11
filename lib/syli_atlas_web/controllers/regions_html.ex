defmodule SyliAtlasWeb.RegionsHTML do
  use SyliAtlasWeb, :html
  alias SyliAtlas.Geo.Area
  alias SyliAtlasWeb.{Charts, Pagination}

  embed_templates "regions_html/*"

  @doc "CSS colour token of an area's line."
  def color("africa"), do: "--ink"
  def color("WLD"), do: "--ink-subtle"
  def color(region), do: "--r-" <> region

  def indicator_tab("gdp_usd_bn"), do: gettext("GDP in dollars")
  def indicator_tab("real_gdp_index"), do: gettext("Real GDP")
  def indicator_tab("gdp_per_capita_usd"), do: gettext("GDP per capita")
  def indicator_tab("real_gdp_growth"), do: gettext("Growth")
  def indicator_tab("inflation"), do: gettext("Inflation")
  def indicator_tab("public_debt_pct_gdp"), do: gettext("Public debt")

  @doc "A link to this page with one parameter changed."
  def link_with(locale, kept, key, value),
    do: Pagination.href(Paths.regions(locale), kept, key, value)

  @doc """
  Chart series: real GDP rebased to 100 in `from`, other indicators as they
  are. GDP in dollars leaves the world out: its scale would flatten Africa.
  """
  def series(areas, indicator, from, focus, locale) do
    areas
    |> Enum.reject(&(indicator == "gdp_usd_bn" and &1["profile"]["code"] == "WLD"))
    |> Enum.map(fn a ->
      p = a["profile"]
      values = p["series"][indicator] || []
      values = if indicator == "real_gdp_index", do: Charts.rebase(values, from), else: values

      %{
        id: p["code"],
        name: SyliAtlas.Locales.pick(p["name"], locale),
        color: color(p["code"]),
        values: values,
        strong: p["code"] == "africa" or p["code"] == focus
      }
    end)
  end

  @doc "Ranked rows for the side card: a change over the period, or the value in `to`."
  def ranked(areas, indicator, to, locale) do
    areas
    |> Enum.map(fn a ->
      p = a["profile"]

      value =
        if indicator in ["gdp_usd_bn", "real_gdp_index", "gdp_per_capita_usd"],
          do: a["period"]["changes"][indicator],
          else: PublicData.at(p["series"][indicator], to)

      %{
        "code" => p["code"],
        "name" => SyliAtlas.Locales.pick(p["name"], locale),
        "slug" => SyliAtlas.Locales.pick(p["slug"], locale),
        "kind" => p["kind"],
        "value" => value
      }
    end)
    |> Enum.sort_by(&(-(&1["value"] || -1.0e9)))
  end

  def ranked_mode(indicator)
      when indicator in ["gdp_usd_bn", "real_gdp_index", "gdp_per_capita_usd"],
      do: "change"

  def ranked_mode(_), do: "value"

  def ranked_title("gdp_usd_bn", from, to),
    do: gettext("GDP in current dollars, %{from} → %{to}", from: from, to: to)

  def ranked_title("real_gdp_index", from, to),
    do: gettext("Real GDP, %{from} → %{to}", from: from, to: to)

  def ranked_title("gdp_per_capita_usd", from, to),
    do: gettext("GDP per capita, %{from} → %{to}", from: from, to: to)

  def ranked_title(ind, _from, to), do: indicator_tab(ind) <> " · " <> to_string(to)

  def table_rows(areas) do
    {africa, rest} = Enum.split_with(areas, &(&1["profile"]["code"] == "africa"))
    {world, regions} = Enum.split_with(rest, &(&1["profile"]["code"] == "WLD"))
    africa ++ regions ++ world
  end
end
