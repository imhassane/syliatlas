defmodule SyliAtlasWeb.PageController do
  use SyliAtlasWeb, :controller

  alias SyliAtlas.{Geo, Sources}
  alias SyliAtlas.Profiles.Builder
  alias SyliAtlasWeb.{Paths, PublicData, Seo}

  plug :put_layout, false

  def root(conn, opts), do: SyliAtlasWeb.Plugs.Locale.redirect_root(conn, opts)

  @default_map_country "CIV"

  def home(conn, params) do
    locale = conn.assigns.locale
    {from, to} = Builder.default_period()

    case PublicData.area("africa", from, to) do
      nil ->
        render(conn, :empty, page_title: "Syli Atlas", seo: %{noindex: true}, alternates: [])

      africa ->
        ranking = PublicData.ranking("gdp_usd_bn", from, to, locale: locale)

        regions =
          Geo.list_regions()
          |> Enum.map(&PublicData.area(&1.code, from, to))
          |> Enum.reject(&is_nil/1)
          |> Enum.sort_by(&(-(&1["period"]["changes"]["gdp_usd_bn"] || -999)))

        paths = %{"fr" => "/fr", "en" => "/en"}
        map = PublicData.map(locale) || %{"countries" => [], "from" => from, "to" => to}
        map_countries = map["countries"]

        map_selected =
          Enum.find(map_countries, &(&1["code"] == params["pays"])) ||
            Enum.find(map_countries, &(&1["code"] == @default_map_country)) ||
            List.first(map_countries)

        render(conn, :home,
          page_title: gettext("African economies, country by country"),
          seo:
            Seo.page(
              locale,
              paths,
              gettext(
                "Growth, living standards, debt and inflation for every African country, from 2015 to the IMF projections for 2030."
              )
            ),
          alternates: Seo.alternates_for_header(paths),
          from: from,
          to: to,
          africa: africa,
          ssa: PublicData.area("SSA", from, to),
          world: PublicData.area("WLD", from, to),
          top: Enum.take(ranking, 3),
          bottom: ranking |> Enum.reject(&is_nil(&1["value"])) |> Enum.take(-3) |> Enum.reverse(),
          regions: regions,
          map_countries: map_countries,
          map_selected: map_selected,
          map_from: map["from"],
          map_to: map["to"],
          map_indicator:
            if(SyliAtlasWeb.MapScale.valid?(params["carte"]), do: params["carte"], else: "gdp"),
          popular:
            ~w(CIV NGA ETH SEN KEN) |> Enum.map(&Geo.get_area_by_code/1) |> Enum.reject(&is_nil/1),
          source: Sources.get_source("imf_weo"),
          edition: Sources.published_edition("imf_weo")
        )
    end
  end

  def method(conn, _params) do
    locale = conn.assigns.locale
    paths = %{"fr" => Paths.method("fr"), "en" => Paths.method("en")}

    render(conn, :method,
      page_title: gettext("Method and sources"),
      seo:
        Seo.page(
          locale,
          paths,
          gettext("Where Syli Atlas figures come from and how totals and changes are computed.")
        ),
      alternates: Seo.alternates_for_header(paths),
      edition: Sources.published_edition("imf_weo"),
      sources: Sources.list_sources()
    )
  end
end
