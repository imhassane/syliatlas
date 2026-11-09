defmodule SyliAtlas.Sources.Indicators do
  @moduledoc """
  The indicators the platform publishes, with their IMF DataMapper codes.

  `kind: :rate` values change in percentage points; `kind: :level` values
  change in percent. `real_gdp_index` is derived from `real_gdp_growth`.
  """

  @indicators [
    %{key: "real_gdp_growth", imf: "NGDP_RPCH", kind: :rate, good: :up},
    %{key: "gdp_usd_bn", imf: "NGDPD", kind: :level, good: :up},
    %{key: "gdp_per_capita_usd", imf: "NGDPDPC", kind: :level, good: :up},
    %{key: "gdp_per_capita_ppp", imf: "PPPPC", kind: :level, good: :up},
    %{key: "inflation", imf: "PCPIPCH", kind: :rate, good: :down},
    %{key: "public_debt_pct_gdp", imf: "GGXWDG_NGDP", kind: :rate, good: :down},
    %{key: "population_m", imf: "LP", kind: :level, good: :neutral}
  ]

  @derived %{key: "real_gdp_index", imf: nil, kind: :index, good: :up}

  @first_year 2015
  @last_year 2030

  def all, do: @indicators
  def keys, do: Enum.map(@indicators, & &1.key)
  def published_keys, do: ["real_gdp_index" | keys()]
  def get(key), do: Enum.find([@derived | @indicators], &(&1.key == key))
  def valid?(key), do: get(key) != nil

  def first_year, do: @first_year
  def last_year, do: @last_year
  def years, do: Enum.to_list(@first_year..@last_year)

  @doc "Last year with published data; later years are estimates or projections."
  def status_for(year, %{estimate_from: est, projection_from: proj}) do
    cond do
      year >= proj -> "projection"
      year >= est -> "estimate"
      true -> "actual"
    end
  end
end
