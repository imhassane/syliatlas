defmodule SyliAtlasWeb.BudgetHTML do
  use SyliAtlasWeb, :html
  alias SyliAtlas.Geo.Area
  alias SyliAtlasWeb.BudgetComponents

  embed_templates "budget_html/*"

  def href(locale, region, sort) do
    query =
      [region && {"region", region.code}, sort != "expenditure" && {"sort", sort}]
      |> Enum.filter(& &1)

    Paths.budgets(locale) <> if(query == [], do: "", else: "?" <> URI.encode_query(query))
  end

  def region_name(region, locale), do: Area.name(region, locale)
  def pct(v, locale), do: BudgetComponents.pct(v, locale)
end
