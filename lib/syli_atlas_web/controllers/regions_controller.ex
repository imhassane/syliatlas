defmodule SyliAtlasWeb.RegionsController do
  @moduledoc "The five regions of the African Union side by side, with Africa and the world."
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Geo.Area
  alias SyliAtlasWeb.{PageComponents, Paths, PublicData, Seo}

  plug :put_layout, false

  @indicators ~w(gdp_usd_bn gdp_per_capita_usd real_gdp_growth inflation public_debt_pct_gdp)

  def index(conn, params) do
    locale = conn.assigns.locale
    {from, to} = PageComponents.period(params)

    indicator =
      if params["indicator"] in @indicators, do: params["indicator"], else: "gdp_usd_bn"

    data = PublicData.regions(locale, from, to)
    regions = Enum.map(data["regions"], &region/1)
    by_code = Map.new(regions, &{&1.code, &1})
    focus = Enum.find_value(regions, &(&1.code == params["focus"] && &1.code))

    paths = %{"fr" => Paths.regions("fr"), "en" => Paths.regions("en")}
    kept = Map.take(params, ~w(indicator from to focus))
    filtered? = map_size(kept) > 0

    render(conn, :index,
      communities: SyliAtlasWeb.CommunityController.summaries(),
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
      areas: data["areas"],
      map_countries: (data["map"] || %{"countries" => []})["countries"],
      carry: Enum.map(data["carry"], &carry(&1, by_code))
    )
  end

  # The region's fields as stored in the snapshot, as the struct the template takes.
  defp region(fields) do
    %Area{
      code: fields["code"],
      kind: fields["kind"],
      name_fr: fields["name_fr"],
      name_en: fields["name_en"],
      slug_fr: fields["slug_fr"],
      slug_en: fields["slug_en"]
    }
  end

  defp carry(c, by_code) do
    %{
      region: Map.fetch!(by_code, c["region"]),
      count: c["count"],
      heavy: c["heavy"],
      fastest: c["fastest"],
      slowest: c["slowest"]
    }
  end
end
