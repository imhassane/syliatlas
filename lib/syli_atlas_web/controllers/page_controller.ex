defmodule SyliAtlasWeb.PageController do
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Sources
  alias SyliAtlasWeb.{Paths, PublicData, Seo}

  plug :put_layout, false

  def root(conn, opts), do: SyliAtlasWeb.Plugs.Locale.redirect_root(conn, opts)

  @default_map_country "CIV"

  @doc """
  The home page reads one snapshot (`SyliAtlas.Profiles.HomeSnapshot`):
  one query per visit. It holds figures; texts stay in the template.
  """
  def home(conn, params) do
    locale = conn.assigns.locale

    case PublicData.home(locale) do
      %{"africa" => africa} = home when is_map(africa) ->
        paths = %{"fr" => "/fr", "en" => "/en"}
        map = home["map"] || %{"countries" => [], "from" => home["from"], "to" => home["to"]}
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
          from: home["from"],
          to: home["to"],
          africa: africa,
          world: home["world"],
          top: home["top"],
          bottom: home["bottom"],
          regions: home["regions"],
          map_countries: map_countries,
          map_selected: map_selected,
          map_from: map["from"],
          map_to: map["to"],
          map_indicator:
            if(SyliAtlasWeb.MapScale.valid?(params["carte"]), do: params["carte"], else: "gdp"),
          popular: home["popular"],
          edition: home["edition"],
          last_checked_at: home["last_checked_at"]
        )

      _ ->
        render(conn, :empty, page_title: "Syli Atlas", seo: %{noindex: true}, alternates: [])
    end
  end

  @doc """
  What the service worker shows when a page is asked offline and is not
  saved on the device (saved at install, under the asked address). Its
  script fills in the asked page and the pages saved, from the cache.
  """
  def offline(conn, _params) do
    locale = conn.assigns.locale
    paths = %{"fr" => Paths.offline("fr"), "en" => Paths.offline("en")}

    render(conn, :offline,
      page_title: gettext("Offline"),
      seo:
        Seo.page(locale, paths, gettext("This page is not saved on this device yet."), %{
          noindex: true
        }),
      alternates: Seo.alternates_for_header(paths),
      entries: SyliAtlasWeb.OfflinePages.entries(locale)
    )
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
