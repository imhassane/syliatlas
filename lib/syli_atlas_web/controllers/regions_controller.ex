defmodule SyliAtlasWeb.RegionsController do
  @moduledoc "The five regions of the African Union side by side, with Africa and the world."
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Geo
  alias SyliAtlasWeb.{PageComponents, Paths, PublicData, Seo}

  plug :put_layout, false

  @indicators ~w(gdp_usd_bn real_gdp_index gdp_per_capita_usd real_gdp_growth inflation public_debt_pct_gdp)

  def index(conn, params) do
    locale = conn.assigns.locale
    {from, to} = PageComponents.period(params)

    indicator =
      if params["indicator"] in @indicators, do: params["indicator"], else: "gdp_usd_bn"

    regions = Geo.list_regions()
    focus = Enum.find_value(regions, &(&1.code == params["focus"] && &1.code))

    areas =
      (Enum.map(regions, & &1.code) ++ ["africa", "WLD"])
      |> Enum.map(&PublicData.area(&1, from, to))
      |> Enum.reject(&is_nil/1)

    paths = %{"fr" => Paths.regions("fr"), "en" => Paths.regions("en")}
    kept = Map.take(params, ~w(indicator from to focus))
    filtered? = map_size(kept) > 0

    render(conn, :index,
      page_title: gettext("The regions of Africa compared"),
      seo:
        Seo.page(
          locale,
          paths,
          gettext(
            "North, West, Central, East and Southern Africa side by side: growth, income, inflation and debt, from IMF data."
          ),
          %{
            noindex: filtered?
          }
        ),
      alternates: Seo.alternates_for_header(paths),
      from: from,
      to: to,
      indicator: indicator,
      indicators: @indicators,
      focus: focus,
      kept: kept,
      regions: regions,
      areas: areas,
      map_countries: (PublicData.map(locale) || %{"countries" => []})["countries"],
      carry: Enum.map(regions, &carry(&1, from, to, locale))
    )
  end

  # Who carries a region: the largest economies' share of its GDP in `to`,
  # and its fastest and slowest GDP growth in dollars over the period.
  defp carry(region, from, to, locale) do
    weights =
      PublicData.ranking("gdp_usd_bn", from, to,
        mode: "value",
        region: region.code,
        locale: locale
      )

    growth =
      PublicData.ranking("gdp_usd_bn", from, to, region: region.code, locale: locale)
      |> Enum.filter(&is_number(&1["value"]))

    total = weights |> Enum.map(&(&1["value"] || 0)) |> Enum.sum()

    %{
      region: region,
      count: length(weights),
      heavy:
        weights
        |> Enum.take(3)
        |> Enum.map(
          &Map.put(&1, "share", if(total > 0, do: (&1["value"] || 0) / total * 100, else: 0))
        ),
      fastest: List.first(growth),
      slowest: List.last(growth)
    }
  end
end
