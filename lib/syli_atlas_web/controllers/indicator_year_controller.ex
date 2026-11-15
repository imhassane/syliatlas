defmodule SyliAtlasWeb.IndicatorYearController do
  @moduledoc "One indicator of one country in one year: `/fr/pays/mauritanie/pib-2025`."
  use SyliAtlasWeb, :controller
  import SyliAtlasWeb.Format, only: [names: 2]
  alias SyliAtlas.Geo.Area
  alias SyliAtlasWeb.{IndicatorYear, NotFoundError, Paths, PublicData, Seo}

  def show(conn, area, key, year) do
    locale = conn.assigns.locale
    {from, _to} = SyliAtlas.Profiles.Builder.default_period()
    data = PublicData.area(area.code, from, year) || raise NotFoundError
    profile = data["profile"]
    values = profile["series"][key] || []
    value = PublicData.at(values, year)
    if not is_number(value), do: raise(NotFoundError)

    paths = SyliAtlas.Locales.each(&IndicatorYear.path(&1, area, key, year))

    if conn.request_path != paths[locale] do
      conn |> put_status(301) |> redirect(to: paths[locale])
    else
      name = Area.name(area, locale)
      previous = PublicData.at(values, year - 1)
      status = status(profile, year)
      ranking = PublicData.ranking(key, year, year, mode: "value", locale: locale)
      rank = rank(ranking, area.code)
      ranked = Enum.count(ranking, &is_number(&1["value"]))
      title = title(key, name, year, value, locale)
      answer = answer(key, name, year, value, previous, rank, ranked, status, locale)
      first = SyliAtlas.Sources.Indicators.first_year()
      last = SyliAtlas.Sources.Indicators.last_year()

      rows =
        for y <- max(first, year - 4)..min(last, year + 4) do
          %{year: y, value: PublicData.at(values, y), status: status(profile, y)}
        end

      render(conn, :show,
        page_title: title,
        seo:
          Seo.page(locale, paths, answer, %{
            noindex: year not in IndicatorYear.indexed_years(),
            json_ld: [
              Seo.breadcrumbs([
                {"Syli Atlas", Paths.home(locale)},
                {name, Paths.area(locale, area)},
                {label(key), paths[locale]}
              ]),
              Seo.dataset(
                name: title,
                description: answer,
                path: paths[locale],
                area: %{name: name, code: area.code},
                temporal: Integer.to_string(year),
                variables: [{label(key), unit(key)}],
                based_on: {edition_label(profile), nil},
                locale: locale
              )
            ]
          }),
        alternates: Seo.alternates_for_header(paths),
        area: area,
        name: name,
        key: key,
        year: year,
        value: value,
        status: status,
        rank: rank,
        ranked: ranked,
        answer: answer,
        title: title,
        rows: rows,
        edition: edition_label(profile),
        years: for(y <- IndicatorYear.indexed_years() ++ [last], y != year, y <= last, do: y)
      )
    end
  end

  defp edition_label(%{"edition" => %{"label" => label}}) when is_binary(label),
    do: "IMF, " <> label

  defp edition_label(_), do: "IMF, World Economic Outlook"

  defp status(%{"years" => %{"estimate_from" => est, "projection_from" => proj}}, y)
       when is_integer(est) and is_integer(proj) do
    cond do
      y >= proj -> "projection"
      y >= est -> "estimate"
      true -> "actual"
    end
  end

  defp status(_, _), do: "actual"

  defp rank(ranking, code) do
    case Enum.find_index(ranking, &(&1["code"] == code and is_number(&1["value"]))) do
      nil -> nil
      i -> i + 1
    end
  end

  @doc "The indicator's name."
  def label("gdp_usd_bn"), do: gettext("GDP")
  def label("gdp_per_capita_usd"), do: gettext("GDP per capita")
  def label("real_gdp_growth"), do: gettext("Real GDP growth")
  def label("inflation"), do: gettext("Inflation")
  def label("public_debt_pct_gdp"), do: gettext("Public debt")

  @doc "The unit of a value."
  def unit("gdp_usd_bn"), do: gettext("billions of current US dollars")
  def unit("gdp_per_capita_usd"), do: gettext("current US dollars")
  def unit("public_debt_pct_gdp"), do: gettext("% of GDP")
  def unit(_), do: "%"

  @doc "A value with its unit (« 12,4 Md$ », « 3,1 % »)."
  def value_text(nil, _key, locale), do: SyliAtlasWeb.Format.number(nil, 0, locale)

  def value_text(v, "gdp_usd_bn", locale),
    do: gettext("%{value} billion $", value: SyliAtlasWeb.Format.number(v, 1, locale))

  def value_text(v, "gdp_per_capita_usd", locale),
    do: SyliAtlasWeb.Format.number(v, 0, locale) <> " $"

  def value_text(v, "public_debt_pct_gdp", locale),
    do: gettext("%{value} % of GDP", value: SyliAtlasWeb.Format.number(v, 1, locale))

  def value_text(v, _key, locale), do: SyliAtlasWeb.Format.number(v, 1, locale) <> " %"

  def status_label("projection"), do: gettext("projection")
  def status_label("estimate"), do: gettext("estimate")
  def status_label(_), do: gettext("observed")

  # « PIB de la Mauritanie en 2025 : 12,4 Md$ (FMI) »
  defp title(key, name, year, value, locale) do
    v = value_text(value, key, locale)

    case key do
      "gdp_usd_bn" ->
        gettext("GDP of %{name} in %{year}: %{value} (IMF)", names(name, year: year, value: v))

      "gdp_per_capita_usd" ->
        gettext("GDP per capita of %{name} in %{year}: %{value} (IMF)",
          names(name, year: year, value: v)
        )

      "real_gdp_growth" ->
        gettext("Economic growth of %{name} in %{year}: %{value} (IMF)",
          names(name, year: year, value: v)
        )

      "inflation" ->
        gettext("Inflation in %{name} in %{year}: %{value} (IMF)",
          names(name, year: year, value: v)
        )

      "public_debt_pct_gdp" ->
        gettext("Public debt of %{name} in %{year}: %{value} (IMF)",
          names(name, year: year, value: v)
        )
    end
  end

  @doc "The heading: the indicator, the country, the year."
  def heading("gdp_usd_bn", name, year),
    do: gettext("GDP of %{name} in %{year}", names(name, year: year))

  def heading("gdp_per_capita_usd", name, year),
    do: gettext("GDP per capita of %{name} in %{year}", names(name, year: year))

  def heading("real_gdp_growth", name, year),
    do: gettext("Economic growth of %{name} in %{year}", names(name, year: year))

  def heading("inflation", name, year),
    do: gettext("Inflation in %{name} in %{year}", names(name, year: year))

  def heading("public_debt_pct_gdp", name, year),
    do: gettext("Public debt of %{name} in %{year}", names(name, year: year))

  defp answer(key, name, year, value, previous, rank, ranked, status, locale) do
    main =
      gettext("%{heading}: %{value} (%{status}).",
        heading: heading(key, name, year),
        value: value_text(value, key, locale),
        status: status_label(status)
      )

    change =
      if is_number(previous) do
        gettext("%{previous} in %{last}.",
          previous: value_text(previous, key, locale),
          last: year - 1
        )
      end

    position =
      if rank do
        gettext("Rank %{rank} of %{count} African countries, highest first.",
          rank: rank,
          count: ranked
        )
      end

    [main, change, position] |> Enum.reject(&is_nil/1) |> Enum.join(" ")
  end
end
