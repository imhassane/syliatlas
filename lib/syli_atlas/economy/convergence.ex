defmodule SyliAtlas.Economy.Convergence do
  @moduledoc """
  First-rank convergence criteria of the two CFA franc unions, checked
  against IMF figures. Computed by Syli Atlas and shown as such.

    * UEMOA (Additional Act No. 01/2015/CCEG/UEMOA): overall fiscal
      balance, grants included, of at least −3 % of GDP; average inflation
      of at most 3 %; public debt of at most 70 % of GDP. The IMF's general
      government net lending or borrowing stands in for the overall balance.
    * CEMAC (2016 surveillance framework): reference fiscal balance of at
      least −1.5 % of GDP, inflation of at most 3 %, public debt of at most
      70 % of GDP. The IMF does not publish the reference balance, so that
      criterion is shown as not computed rather than approximated.
  """

  alias SyliAtlas.Economy.Currencies

  @criteria %{
    "uemoa" => [
      %{key: "fiscal_balance", indicator: "fiscal_balance_pct_gdp", op: :gte, limit: -3.0},
      %{key: "inflation", indicator: "inflation", op: :lte, limit: 3.0},
      %{key: "debt", indicator: "public_debt_pct_gdp", op: :lte, limit: 70.0}
    ],
    "cemac" => [
      %{key: "reference_balance", indicator: nil, op: :gte, limit: -1.5},
      %{key: "inflation", indicator: "inflation", op: :lte, limit: 3.0},
      %{key: "debt", indicator: "public_debt_pct_gdp", op: :lte, limit: 70.0}
    ]
  }

  @doc """
  The criteria of a country's union in `year`, or nil outside UEMOA and
  CEMAC. `series` is the profile's `%{indicator => [value per year]}`.
  Each criterion: `%{key, limit, op, value, status: :met | :missed | :no_data | :not_computed}`.
  """
  def check(country_code, series, year, first_year \\ 2015) do
    zone = Currencies.zone(country_code)

    case Map.fetch(@criteria, zone || "") do
      {:ok, criteria} ->
        %{
          zone: zone,
          year: year,
          criteria: Enum.map(criteria, &evaluate(&1, series, year - first_year))
        }

      :error ->
        nil
    end
  end

  defp evaluate(%{indicator: nil} = c, _series, _i),
    do: Map.merge(c, %{value: nil, status: :not_computed})

  defp evaluate(c, series, i) do
    value = series |> Map.get(c.indicator, []) |> Enum.at(i)

    status =
      cond do
        not is_number(value) -> :no_data
        c.op == :gte and value >= c.limit -> :met
        c.op == :lte and value <= c.limit -> :met
        true -> :missed
      end

    Map.merge(c, %{value: value, status: status})
  end
end
