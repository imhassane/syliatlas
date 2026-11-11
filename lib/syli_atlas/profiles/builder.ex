defmodule SyliAtlas.Profiles.Builder do
  @moduledoc """
  Turns the raw observations of an edition into one document per area.

  Pure functions only: the caller loads observations and areas and stores
  the result. Regional and continental totals are computed here because
  the IMF does not publish them:

    * GDP and population are summed;
    * GDP per capita is total GDP divided by total population;
    * growth and inflation are weighted by PPP GDP;
    * public debt, the fiscal balance and the current account are
      weighted by GDP in US dollars;
    * unemployment has no group value: the IMF covers too few countries.

  A country with no value for a year is left out of that year's total.
  """

  alias SyliAtlas.Sources.Indicators

  @default_from 2020
  @default_to 2025

  def default_period, do: {@default_from, @default_to}

  @doc """
  `observations` is `%{area_code => %{indicator => %{year => value}}}`.
  `areas` is a list of `%SyliAtlas.Geo.Area{}`. `meta` holds edition data.
  Returns `%{area_code => doc_map}`.
  """
  def build(observations, areas, meta) do
    years = Indicators.years()
    countries = Enum.filter(areas, &(&1.kind == "country"))

    base =
      areas
      |> Enum.filter(&(&1.kind in ["country", "imf_aggregate"]))
      |> Map.new(fn area ->
        series =
          Map.new(Indicators.keys(), fn key ->
            {key, Enum.map(years, &get_in(observations, [area.code, key, &1]))}
          end)

        {area.code, series}
      end)

    regional =
      areas
      |> Enum.filter(&(&1.kind in ["region", "continent"]))
      |> Map.new(fn area ->
        members =
          if area.kind == "continent",
            do: countries,
            else: Enum.filter(countries, &(&1.region_code == area.code))

        {area.code, aggregate(Enum.map(members, &Map.fetch!(base, &1.code)))}
      end)

    all_series =
      base
      |> Map.merge(regional)
      |> Map.new(fn {code, series} ->
        {code, Map.put(series, "real_gdp_index", volume_index(series["real_gdp_growth"]))}
      end)

    ranks = default_ranks(all_series, countries)
    africa_gdp = all_series["africa"]["gdp_usd_bn"]

    Map.new(areas, fn area ->
      series = Map.fetch!(all_series, area.code)
      {area.code, document(area, series, ranks, africa_gdp, countries, meta)}
    end)
  end

  defp document(area, series, ranks, africa_gdp, countries, meta) do
    {from, to} = default_period()

    %{
      "code" => area.code,
      "kind" => area.kind,
      "name" => %{"fr" => area.name_fr, "en" => area.name_en},
      "slug" => %{"fr" => area.slug_fr, "en" => area.slug_en},
      "region" => area.region_code,
      "edition" => meta.edition,
      "years" => %{
        "first" => Indicators.first_year(),
        "last" => Indicators.last_year(),
        "estimate_from" => meta.estimate_from,
        "projection_from" => meta.projection_from
      },
      "series" => Map.new(series, fn {k, v} -> {k, Enum.map(v, &round_value/1)} end),
      "share_of_africa_gdp" => share(series["gdp_usd_bn"], africa_gdp),
      "missing" => missing(series, area.kind),
      "members" => members(area, countries),
      "default_period" => %{
        "from" => from,
        "to" => to,
        "real_gdp_change_pct" => change(series["real_gdp_index"], from, to, :level),
        "rank" => Map.get(ranks, area.code)
      }
    }
  end

  @doc "Chains yearly growth rates into an index where the first year is 100."
  def volume_index([_first | rest]) do
    rest
    |> Enum.reduce([100.0], fn
      growth, [prev | _] = acc when is_number(growth) and is_number(prev) ->
        [prev * (1 + growth / 100) | acc]

      _growth, acc ->
        [nil | acc]
    end)
    |> Enum.reverse()
  end

  @doc "Change between two years: percent for levels and indexes, points for rates."
  def change(values, from, to, kind) do
    a = Enum.at(values, from - Indicators.first_year())
    b = Enum.at(values, to - Indicators.first_year())

    cond do
      not (is_number(a) and is_number(b)) -> nil
      kind == :rate -> Float.round((b - a) * 1.0, 1)
      a == 0 -> nil
      true -> Float.round((b / a - 1) * 100, 1)
    end
  end

  @doc """
  Totals of a group of countries, by the same rules as regions (sums,
  weighted averages), with its real GDP index. `members` are series maps
  (`%{indicator => [value per year]}`).
  """
  def aggregate_series(members) do
    series = aggregate(members)
    Map.put(series, "real_gdp_index", volume_index(series["real_gdp_growth"]))
  end

  defp aggregate(members) do
    n = length(Indicators.years())

    Map.new(Indicators.keys(), fn key ->
      {key, Enum.map(0..(n - 1), fn i -> aggregate_value(key, members, i) end)}
    end)
  end

  defp aggregate_value(key, members, i) do
    at = fn series, k -> Enum.at(series[k], i) end

    with_all = fn keys ->
      Enum.filter(members, fn s -> Enum.all?(keys, &is_number(at.(s, &1))) end)
    end

    ppp_weight = fn s -> at.(s, "gdp_per_capita_ppp") * at.(s, "population_m") end

    case key do
      k when k in ["gdp_usd_bn", "population_m"] ->
        sum_or_nil(with_all.([k]), &at.(&1, k))

      "gdp_per_capita_usd" ->
        rows = with_all.(["gdp_usd_bn", "population_m"])

        ratio(
          sum_or_nil(rows, &at.(&1, "gdp_usd_bn")),
          sum_or_nil(rows, &at.(&1, "population_m")),
          1000
        )

      "gdp_per_capita_ppp" ->
        rows = with_all.(["gdp_per_capita_ppp", "population_m"])
        ratio(sum_or_nil(rows, ppp_weight), sum_or_nil(rows, &at.(&1, "population_m")), 1)

      k when k in ["real_gdp_growth", "inflation"] ->
        rows = with_all.([k, "gdp_per_capita_ppp", "population_m"])
        ratio(sum_or_nil(rows, &(at.(&1, k) * ppp_weight.(&1))), sum_or_nil(rows, ppp_weight), 1)

      k when k in ["public_debt_pct_gdp", "fiscal_balance_pct_gdp", "current_account_pct_gdp"] ->
        rows = with_all.([key, "gdp_usd_bn"])

        ratio(
          sum_or_nil(rows, &(at.(&1, key) * at.(&1, "gdp_usd_bn"))),
          sum_or_nil(rows, &at.(&1, "gdp_usd_bn")),
          1
        )

      # Too few African countries have an IMF unemployment rate for a
      # group average to mean anything.
      "unemployment" ->
        nil
    end
  end

  defp sum_or_nil([], _fun), do: nil
  defp sum_or_nil(rows, fun), do: rows |> Enum.map(fun) |> Enum.sum()

  defp ratio(nil, _b, _k), do: nil
  defp ratio(_a, nil, _k), do: nil
  defp ratio(_a, b, _k) when b == 0, do: nil
  defp ratio(a, b, k), do: a * k / b

  defp share(nil, _total), do: nil

  defp share(values, total) do
    values
    |> Enum.zip(total)
    |> Enum.map(fn
      {v, t} when is_number(v) and is_number(t) and t > 0 -> Float.round(100 * v / t, 1)
      _ -> nil
    end)
  end

  # Groups have no unemployment rate by design (see the moduledoc): it is
  # not a gap.
  @not_aggregated ["real_gdp_index", "unemployment"]

  defp missing(series, kind) do
    skip = if kind in ["region", "continent"], do: @not_aggregated, else: ["real_gdp_index"]

    series
    |> Enum.filter(fn {key, values} ->
      key not in skip and Enum.any?(values, &is_nil/1)
    end)
    |> Enum.map(fn {key, values} ->
      years =
        values
        |> Enum.with_index(Indicators.first_year())
        |> Enum.filter(fn {v, _} -> is_nil(v) end)
        |> Enum.map(&elem(&1, 1))

      %{"indicator" => key, "years" => years}
    end)
    |> Enum.sort_by(& &1["indicator"])
  end

  defp members(%{kind: "region", code: code}, countries),
    do: countries |> Enum.filter(&(&1.region_code == code)) |> Enum.map(& &1.code) |> Enum.sort()

  defp members(%{kind: "continent"}, countries),
    do: countries |> Enum.map(& &1.code) |> Enum.sort()

  defp members(%{kind: "country", region_code: region}, countries),
    do:
      countries |> Enum.filter(&(&1.region_code == region)) |> Enum.map(& &1.code) |> Enum.sort()

  defp members(_area, _countries), do: []

  defp default_ranks(all_series, countries) do
    {from, to} = default_period()

    scored =
      countries
      |> Enum.map(&{&1, change(all_series[&1.code]["real_gdp_index"], from, to, :level)})
      |> Enum.filter(fn {_c, v} -> is_number(v) end)
      |> Enum.sort_by(fn {_c, v} -> -v end)

    africa_total = length(scored)

    Map.new(scored, fn {country, _v} ->
      in_region = Enum.filter(scored, fn {c, _} -> c.region_code == country.region_code end)

      {country.code,
       %{
         "africa" => position(scored, country),
         "of_africa" => africa_total,
         "region" => position(in_region, country),
         "of_region" => length(in_region)
       }}
    end)
  end

  defp position(list, country),
    do: Enum.find_index(list, fn {c, _} -> c.code == country.code end) + 1

  defp round_value(nil), do: nil
  defp round_value(v) when is_number(v), do: Float.round(v * 1.0, 3)
end
