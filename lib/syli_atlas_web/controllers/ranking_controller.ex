defmodule SyliAtlasWeb.RankingController do
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Geo
  alias SyliAtlas.Sources.Indicators
  alias SyliAtlasWeb.{PageComponents, Pagination, Paths, PublicData, Seo}

  plug :put_layout, false

  def index(conn, params) do
    locale = conn.assigns.locale
    {from, to} = PageComponents.period(params)

    indicator =
      if Indicators.valid?(params["indicator"]), do: params["indicator"], else: "gdp_usd_bn"

    # The value in the arrival year by default; the change over the period on
    # demand. Real GDP is an index (100 = the start year): only its change means
    # something.
    mode =
      if params["mode"] == "change" or indicator == "real_gdp_index", do: "change", else: "value"

    region = Enum.find(Geo.list_regions(), &(&1.code == params["region"]))

    rows =
      PublicData.ranking(indicator, from, to,
        mode: mode,
        region: region && region.code,
        locale: locale
      )

    {ranked, missing} = Enum.split_with(rows, &is_number(&1["value"]))
    ranked = if params["order"] == "asc", do: Enum.reverse(ranked), else: ranked
    page = Pagination.paginate(ranked, params["page"])
    kept = Map.take(params, ~w(indicator mode region order from to))
    paths = %{"fr" => Paths.ranking("fr"), "en" => Paths.ranking("en")}
    filtered? = map_size(kept) > 0 or page.page > 1

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
      page: page,
      page_href: &Pagination.href(Paths.ranking(locale), kept, "page", &1, "ranking"),
      missing: missing,
      # Bars keep one scale across pages: the largest value of the ranking.
      bar_max: ranked |> Enum.map(&abs(&1["value"])) |> Enum.max(fn -> 0 end)
    )
  end
end
