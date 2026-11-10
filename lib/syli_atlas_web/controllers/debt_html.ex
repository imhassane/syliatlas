defmodule SyliAtlasWeb.DebtHTML do
  use SyliAtlasWeb, :html
  alias SyliAtlas.Geo.Area
  alias SyliAtlasWeb.WorldBankComponents

  embed_templates "debt_html/*"

  def href(locale, region, sort) do
    query =
      [region && {"region", region.code}, sort != "debt" && {"sort", sort}]
      |> Enum.filter(& &1)

    Paths.debt(locale) <> if(query == [], do: "", else: "?" <> URI.encode_query(query))
  end

  def region_name(region, locale), do: Area.name(region, locale)

  def usd(v, locale), do: SyliAtlasWeb.WorldBankComponents.usd(v, locale)

  def pct(nil, _), do: "—"
  def pct(v, locale), do: SyliAtlasWeb.Format.number(v, 1, locale) <> " %"
end
