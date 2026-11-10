defmodule SyliAtlas.WorldBank do
  @moduledoc """
  Debt, financial flows, structure of the economy, jobs and living
  conditions of African countries, from two World Bank databases
  (CC BY 4.0):

    * International Debt Statistics (IDS): external debt by creditor,
      including what is owed to China, and its service;
    * World Development Indicators (WDI): investment, remittances and aid
      inflows, value added by sector, the ILO modelled labour estimates,
      poverty, electricity, internet and accounts.

  Some WDI series are compiled by other bodies (ILO for jobs, OECD for aid,
  IMF for the balance of payments): each series names its origin, shown
  under the figures. The IMF stays the source of GDP, debt as a share of
  GDP and the other WEO series; World Bank figures are never mixed into
  them.

  The bundled file is `priv/data/world_bank.json` (`mix world_bank.refresh`
  updates it from api.worldbank.org). Kept in memory: pages add no query.
  """

  @first_year 2015
  @last_year 2025

  # key => {World Bank code, database, origin when the Bank republishes another body's data}
  @series [
    # IDS: public and publicly guaranteed (PPG) external debt by creditor, current US$.
    {"external_debt_usd", "DT.DOD.DECT.CD", :ids, nil},
    {"ppg_debt_usd", "DT.DOD.DPPG.CD", :ids, nil},
    {"ppg_multilateral_usd", "DT.DOD.MLAT.CD", :ids, nil},
    {"ppg_bilateral_usd", "DT.DOD.BLAT.CD", :ids, nil},
    {"ppg_china_usd", "DT.DOD.BLAT.CD", {:ids, "730"}, nil},
    {"ppg_bonds_usd", "DT.DOD.PBND.CD", :ids, nil},
    {"ppg_banks_usd", "DT.DOD.PCBK.CD", :ids, nil},
    {"ppg_other_private_usd", "DT.DOD.PROP.CD", :ids, nil},
    {"ppg_service_usd", "DT.TDS.DPPG.CD", :ids, nil},
    {"ppg_service_pct_exports", "DT.TDS.DPPG.XP.ZS", :wdi, nil},
    # WDI: inflows.
    {"fdi_pct_gdp", "BX.KLT.DINV.WD.GD.ZS", :wdi, "imf_bop"},
    {"remittances_pct_gdp", "BX.TRF.PWKR.DT.GD.ZS", :wdi, "knomad"},
    {"oda_pct_gni", "DT.ODA.ODAT.GN.ZS", :wdi, "oecd"},
    {"fdi_usd", "BX.KLT.DINV.CD.WD", :wdi, "imf_bop"},
    {"remittances_usd", "BX.TRF.PWKR.CD.DT", :wdi, "knomad"},
    {"oda_usd", "DT.ODA.ODAT.CD", :wdi, "oecd"},
    # WDI: structure of the economy.
    {"agriculture_pct_gdp", "NV.AGR.TOTL.ZS", :wdi, nil},
    {"industry_pct_gdp", "NV.IND.TOTL.ZS", :wdi, nil},
    {"manufacturing_pct_gdp", "NV.IND.MANF.ZS", :wdi, nil},
    {"services_pct_gdp", "NV.SRV.TOTL.ZS", :wdi, nil},
    # WDI: ILO modelled estimates.
    {"unemployment_ilo", "SL.UEM.TOTL.ZS", :wdi, "ilo"},
    {"youth_unemployment", "SL.UEM.1524.ZS", :wdi, "ilo"},
    {"female_participation", "SL.TLF.CACT.FE.ZS", :wdi, "ilo"},
    {"vulnerable_employment", "SL.EMP.VULN.ZS", :wdi, "ilo"},
    {"jobs_agriculture", "SL.AGR.EMPL.ZS", :wdi, "ilo"},
    {"jobs_industry", "SL.IND.EMPL.ZS", :wdi, "ilo"},
    {"jobs_services", "SL.SRV.EMPL.ZS", :wdi, "ilo"},
    # WDI: living conditions.
    {"poverty", "SI.POV.DDAY", :wdi, nil},
    {"gini", "SI.POV.GINI", :wdi, nil},
    {"electricity", "EG.ELC.ACCS.ZS", :wdi, nil},
    {"internet", "IT.NET.USER.ZS", :wdi, nil},
    {"accounts", "FX.OWN.TOTL.ZS", :wdi, nil}
  ]

  # Lower is better for these; the others are neutral or higher is better.
  @lower_is_better ~w(poverty gini unemployment_ilo youth_unemployment vulnerable_employment ppg_service_pct_exports)

  @key {__MODULE__, :document}

  def series, do: @series
  def keys, do: Enum.map(@series, &elem(&1, 0))
  def first_year, do: @first_year
  def last_year, do: @last_year
  def path, do: Application.app_dir(:syli_atlas, "priv/data/world_bank.json")
  def lower_is_better?(key), do: key in @lower_is_better

  @doc "The origin of a series when the World Bank republishes another body's data."
  def origin(key) do
    Enum.find_value(@series, fn {k, _code, _db, origin} -> if k == key, do: origin end)
  end

  def database(key) do
    Enum.find_value(@series, fn
      {^key, _code, {db, _}, _} -> db
      {^key, _code, db, _} -> db
      _ -> nil
    end)
  end

  @doc "The built document: sources, and per country every series with its latest value."
  def document do
    case :persistent_term.get(@key, nil) do
      nil ->
        doc =
          if File.exists?(path()),
            do: path() |> File.read!() |> Jason.decode!() |> build(),
            else: build(%{"countries" => %{}})

        :persistent_term.put(@key, doc)
        doc

      doc ->
        doc
    end
  end

  @doc "Forgets the document in memory, so the next read loads the file again."
  def reload!, do: :persistent_term.erase(@key)

  @doc "A country's entry, or nil when the World Bank has nothing for it."
  def for_country(code) do
    entry = document()["countries"][code]
    if entry && map_size(entry["latest"]) > 0, do: entry
  end

  @doc false
  def build(%{"countries" => raw} = file) do
    latest =
      Map.new(raw, fn {code, series} -> {code, latest(series)} end)

    medians =
      Map.new(keys(), fn key ->
        values = for {_c, l} <- latest, v = l[key], v != nil, do: v["value"]
        {key, median(values)}
      end)

    countries =
      Map.new(raw, fn {code, series} ->
        l = latest[code]

        {code,
         %{
           "series" => series,
           "latest" => l,
           "creditors" => creditors(series),
           "creditors_history" =>
             for(
               year <- [2015, 2020],
               shares = creditors(series, year),
               shares != nil,
               do: shares
             )
         }}
      end)

    %{
      "as_of" => file["as_of"],
      "sources" => file["sources"] || %{},
      "medians" => medians,
      "countries" => countries
    }
  end

  # Latest year with a value, per series: %{key => %{"year", "value"}}.
  defp latest(series) do
    for {key, by_year} <- series,
        is_map(by_year),
        {year, value} <-
          by_year
          |> Enum.filter(fn {_y, v} -> is_number(v) end)
          |> Enum.max_by(fn {y, _v} -> y end, fn -> nil end)
          |> List.wrap(),
        into: %{} do
      {key, %{"year" => String.to_integer(year), "value" => value}}
    end
  end

  @doc """
  Shares of the public external debt by creditor, in the latest year where
  the total is known (or the given year): multilateral, China, other
  countries, bonds, banks and other private lenders. Nil without a total.
  """
  def creditors(series, year \\ nil) do
    total = series["ppg_debt_usd"] || %{}

    year =
      year ||
        total
        |> Enum.filter(fn {_y, v} -> is_number(v) and v > 0 end)
        |> Enum.map(&elem(&1, 0))
        |> Enum.max(fn -> nil end)

    year = year && to_string(year)
    get = fn key -> get_in(series, [key, year]) end

    with t when is_number(t) and t > 0 <- year && get.("ppg_debt_usd") do
      bilateral = get.("ppg_bilateral_usd") || 0
      china = get.("ppg_china_usd") || 0
      private = (get.("ppg_banks_usd") || 0) + (get.("ppg_other_private_usd") || 0)

      shares = %{
        "multilateral" => get.("ppg_multilateral_usd") || 0,
        "china" => china,
        "other_bilateral" => max(bilateral - china, 0),
        "bonds" => get.("ppg_bonds_usd") || 0,
        "private" => private
      }

      %{
        "year" => String.to_integer(year),
        "total_usd" => t,
        "shares" => Map.new(shares, fn {k, v} -> {k, Float.round(100 * v / t, 1)} end)
      }
    else
      _ -> nil
    end
  end

  defp median([]), do: nil

  defp median(values) do
    sorted = Enum.sort(values)
    n = length(sorted)
    mid = div(n, 2)

    if rem(n, 2) == 1,
      do: Enum.at(sorted, mid),
      else: (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
  end
end
