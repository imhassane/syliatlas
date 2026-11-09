defmodule SyliAtlasWeb.RankingController do
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Geo
  alias SyliAtlas.Sources.Indicators
  alias SyliAtlasWeb.{PageComponents, Paths, PublicData, Seo}

  plug :put_layout, false

  def index(conn, params) do
    locale = conn.assigns.locale
    {from, to} = PageComponents.period(params)

    indicator =
      if Indicators.valid?(params["indicator"]), do: params["indicator"], else: "real_gdp_index"

    mode =
      if params["mode"] == "value" and indicator != "real_gdp_index", do: "value", else: "change"

    region = Enum.find(Geo.list_regions(), &(&1.code == params["region"]))

    rows =
      PublicData.ranking(indicator, from, to,
        mode: mode,
        region: region && region.code,
        locale: locale
      )

    {ranked, missing} = Enum.split_with(rows, &is_number(&1["value"]))
    ranked = if params["order"] == "asc", do: Enum.reverse(ranked), else: ranked
    paths = %{"fr" => Paths.ranking("fr"), "en" => Paths.ranking("en")}
    filtered? = params |> Map.take(~w(indicator mode region order from to)) |> map_size() > 0

    render(conn, :index,
      page_title: gettext("Ranking of African economies"),
      seo:
        Seo.page(
          locale,
          paths,
          gettext(
            "All African countries ranked by growth, income, inflation and debt, from IMF data."
          ),
          %{
            noindex: filtered?
          }
        ),
      alternates: Seo.alternates_for_header(paths),
      from: from,
      to: to,
      indicator: indicator,
      mode: mode,
      region: region,
      regions: Geo.list_regions(),
      order: params["order"] || "desc",
      rows: ranked,
      missing: missing,
      max: ranked |> Enum.map(&abs(&1["value"])) |> Enum.max(fn -> 1 end)
    )
  end
end
