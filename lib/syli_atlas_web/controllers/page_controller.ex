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
          page_title: gettext("Economic data of the 54 African countries: GDP, debt, inflation"),
          seo:
            Seo.page(
              locale,
              paths,
              gettext(
                "Growth, living standards, debt and inflation for every African country, from 2015 to the IMF projections for 2030."
              ),
              %{json_ld: Seo.site(locale)}
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
          ratings: SyliAtlas.Ratings.document(),
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
      page_title: gettext("Sources and method: IMF, World Bank, CEPII, rating agencies"),
      seo:
        Seo.page(
          locale,
          paths,
          gettext("Where Syli Atlas figures come from and how totals and changes are computed.")
        ),
      alternates: Seo.alternates_for_header(paths),
      edition: Sources.published_edition("imf_weo"),
      data_sources: data_sources(Sources.published_edition("imf_weo"))
    )
  end

  # The accessibility statement (RGAA). Update after each audit made in Ara
  # (https://ara.numerique.gouv.fr): status :none | :partial | :full, the
  # rate it gives, the date, and the pages left non-compliant.
  @accessibility %{
    status: :none,
    rate: nil,
    audited_on: nil,
    stated_on: ~D[2026-11-11],
    rgaa: "4.1.2"
  }

  @doc "The accessibility status, for the footer mention."
  def accessibility_status, do: @accessibility.status

  def accessibility(conn, _params) do
    locale = conn.assigns.locale
    paths = %{"fr" => Paths.accessibility("fr"), "en" => Paths.accessibility("en")}

    template = if locale == "en", do: :accessibility_en, else: :accessibility_fr

    render(conn, template,
      page_title: gettext("Accessibility"),
      seo:
        Seo.page(
          locale,
          paths,
          gettext(
            "Accessibility statement of Syli Atlas: compliance with the RGAA, known barriers and how to report one."
          )
        ),
      alternates: Seo.alternates_for_header(paths),
      a11y: @accessibility,
      contact_email: Application.get_env(:syli_atlas, :site, [])[:contact_email]
    )
  end

  defp trade_sources do
    case SyliAtlas.Trade.document()["source"] do
      nil ->
        []

      s ->
        [
          %{
            id: "baci",
            name: s["name"],
            url: s["url"],
            what: gettext("Exports and imports of goods by product and partner"),
            terms: gettext("Free reuse with attribution (Licence Ouverte Etalab 2.0)"),
            terms_url: "https://www.etalab.gouv.fr/licence-ouverte-open-licence/",
            updated: gettext("Every year, in January"),
            online:
              gettext("version %{version}, %{nomenclature}",
                version: s["version"],
                nomenclature: s["nomenclature"]
              )
          }
        ]
    end
  end

  defp world_bank_sources do
    sources = SyliAtlas.WorldBank.document()["sources"]

    for {id, what} <- [
          {"ids", gettext("External debt by creditor, including China, and its service")},
          {"wdi",
           gettext(
             "Investment, remittances and aid inflows, value added and jobs by sector (ILO estimates), poverty, electricity, internet, accounts"
           )}
        ],
        s = sources[id] do
      %{
        id: "world_bank_" <> id,
        name: s["name"],
        url: s["url"],
        what: what,
        terms: gettext("Free reuse with attribution (CC BY 4.0)"),
        terms_url: "https://www.worldbank.org/en/about/legal/terms-of-use-for-datasets",
        updated:
          if(id == "ids", do: gettext("Every December"), else: gettext("Several times a year")),
        online: s["last_updated"]
      }
    end
  end

  # The sources the pages actually show, with their terms and the date of
  # what is online. Planned sources are not listed until they are imported.
  defp data_sources(edition) do
    ratings = SyliAtlas.Ratings.document()
    market = if SyliAtlas.Market.public?(), do: SyliAtlas.Market.overview()

    [
      %{
        id: "imf_weo",
        name: gettext("IMF · World Economic Outlook"),
        url: "https://www.imf.org/en/Publications/WEO",
        what:
          gettext(
            "GDP, growth, inflation, public debt, fiscal balance, current account, unemployment, population"
          ),
        terms: gettext("Free reuse with attribution, non-commercial use"),
        terms_url: "https://www.imf.org/en/About/copyright-and-terms",
        updated: gettext("April and October"),
        online: edition && edition.label
      },
      %{
        id: "ratings",
        name: gettext("S&P Global Ratings, Moody's, Fitch Ratings"),
        url: nil,
        what: gettext("Sovereign credit ratings"),
        terms:
          gettext("Read from each agency's release, linked under every rating; never scraped"),
        terms_url: nil,
        updated: gettext("At each decision"),
        online: ratings && ratings["as_of"]
      }
    ] ++
      world_bank_sources() ++
      trade_sources() ++
      [
        %{
          id: "imf_dsa",
          name: gettext("IMF · Debt sustainability analyses of low-income countries"),
          url: SyliAtlas.DebtDistress.document()["source"]["url"],
          what: gettext("Risk of external debt distress, with the date of each analysis"),
          terms: gettext("Public assessment, linked; not recomputed"),
          terms_url: nil,
          updated: gettext("Every quarter"),
          online: SyliAtlas.DebtDistress.document()["as_of"]
        }
      ] ++
      if(market,
        do: [
          %{
            id: "mansa",
            name: "MansaAPI",
            url: "https://mansaapi.com",
            what: gettext("Stock exchange closes and indices, dollar exchange rates"),
            terms:
              gettext("Shown on Syli Atlas with the credit “Data by MansaAPI”; not redistributed"),
            terms_url: "https://mansaapi.com/licensing",
            updated: gettext("Every trading day"),
            online: market["as_of"] && String.slice(to_string(market["as_of"]), 0, 10)
          }
        ],
        else: []
      ) ++
      [
        %{
          id: "currencies",
          name: gettext("ISO 4217 and central banks"),
          url: nil,
          what:
            gettext(
              "Currency codes and fixed parities (CFA francs, Comorian franc, escudo, dobra…)"
            ),
          terms: gettext("Public facts"),
          terms_url: nil,
          updated: gettext("When a parity changes"),
          online: nil
        }
      ]
  end
end
