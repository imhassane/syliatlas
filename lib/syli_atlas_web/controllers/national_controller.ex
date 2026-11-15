defmodule SyliAtlasWeb.NationalController do
  @moduledoc """
  Africa's GDP twice: the IMF's total, and the sum of national figures
  (each country's counted official figure, else the IMF's of the same year),
  country by country, each line with the source it uses.
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.{Geo, National}
  alias SyliAtlasWeb.{Paths, Seo}

  plug :put_layout, false

  def index(conn, params) do
    locale = conn.assigns.locale
    paths = SyliAtlas.Locales.each(&Paths.national/1)
    {_from, default_year} = SyliAtlas.Profiles.Builder.default_period()

    year =
      case Integer.parse(params["year"] || "") do
        {y, ""} when y in 2015..2030 -> y
        _ -> default_year
      end

    doc = National.document()
    africa = National.africa(doc, year)
    names = Map.new(Geo.list_areas(), &{&1.code, Geo.Area.name(&1, locale)})
    slugs = Map.new(Geo.list_areas(), &{&1.code, Geo.Area.slug(&1, locale)})

    rows =
      ((africa && africa["rows"]) || [])
      |> Enum.map(&Map.merge(&1, %{"name" => names[&1["code"]], "slug" => slugs[&1["code"]]}))
      |> Enum.sort_by(&(-(&1["retained"] || -1)))

    answer =
      if africa,
        do:
          gettext(
            "Africa's GDP in %{year}: %{imf} according to the IMF, %{national} as the sum of national figures (%{counted} official, the others IMF figures as fallback).",
            year: year,
            imf: SyliAtlasWeb.Format.value(africa["imf_total"], "gdp_usd_bn", locale),
            national: SyliAtlasWeb.Format.value(africa["national_total"], "gdp_usd_bn", locale),
            counted: africa["counted"]
          ),
        else: gettext("Africa's GDP, IMF and national figures.")

    render(conn, :index,
      page_title: gettext("Africa's GDP: IMF and national figures, country by country"),
      seo:
        Seo.page(locale, paths, answer, %{
          json_ld: [
            Seo.breadcrumbs([
              {"Syli Atlas", Paths.home(locale)},
              {gettext("National figures"), paths[locale]}
            ])
          ]
        }),
      alternates: Seo.alternates_for_header(paths),
      year: year,
      africa: africa,
      rows: rows,
      doc: doc,
      answer: answer
    )
  end

  @doc """
  Every rebasing of national accounts in Africa, newest first: date, bases,
  revision, and whether the IMF has taken it in.
  """
  def rebasings(conn, _params) do
    locale = conn.assigns.locale
    paths = SyliAtlas.Locales.each(&Paths.rebasings/1)
    doc = National.document()
    areas = Geo.list_countries()
    names = Map.new(areas, &{&1.code, Geo.Area.name(&1, locale)})
    by_code = Map.new(areas, &{&1.code, &1})

    rows =
      for n <- National.rebasing_list(doc), by_code[n["country_code"]] do
        Map.merge(n, %{
          "name" => names[n["country_code"]],
          "href" =>
            Paths.area_tab(locale, by_code[n["country_code"]], :economy) <>
              if(n["active"], do: "#rebasage", else: "")
        })
      end

    active = Enum.count(rows, & &1["active"])

    answer =
      case rows do
        [] ->
          gettext("No rebasing of national accounts followed yet.")

        _ ->
          gettext(
            "%{count} rebasings of national accounts followed in Africa, %{active} not yet taken in by the IMF. Date, former and new base year, revision of the GDP and source for each.",
            count: length(rows),
            active: active
          )
      end

    latest = rows |> Enum.map(& &1["announced_on"]) |> Enum.max(fn -> nil end)

    render(conn, :rebasings,
      page_title: gettext("GDP rebasings in Africa, country by country"),
      seo:
        Seo.page(locale, paths, answer, %{
          json_ld: [
            Seo.breadcrumbs([
              {"Syli Atlas", Paths.home(locale)},
              {gettext("GDP rebasings"), paths[locale]}
            ]),
            Seo.dataset(
              name: gettext("GDP rebasings in Africa"),
              description: answer,
              path: paths[locale],
              locale: locale,
              modified: latest,
              keywords: [
                gettext("GDP rebasing"),
                gettext("base year"),
                gettext("national accounts")
              ]
            )
          ]
        }),
      alternates: Seo.alternates_for_header(paths),
      rows: rows,
      active: active,
      answer: answer
    )
  end
end
