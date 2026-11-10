defmodule SyliAtlas.Economy.ConvergenceTest do
  use ExUnit.Case, async: true
  alias SyliAtlas.Economy.{Convergence, Currencies}

  # 2015..2030: index 10 is 2025.
  defp series(balance, inflation, debt) do
    at = fn v -> List.duplicate(nil, 10) ++ [v] ++ List.duplicate(nil, 5) end

    %{
      "fiscal_balance_pct_gdp" => at.(balance),
      "inflation" => at.(inflation),
      "public_debt_pct_gdp" => at.(debt)
    }
  end

  test "UEMOA: the three first-rank criteria, thresholds included" do
    %{zone: "uemoa", criteria: [balance, inflation, debt]} =
      Convergence.check("CIV", series(-3.0, 3.4, 57.1), 2025)

    assert balance.status == :met
    assert inflation.status == :missed
    assert debt.status == :met
    assert debt.value == 57.1
  end

  test "CEMAC: the reference balance is not computed, the others are" do
    %{zone: "cemac", criteria: [ref, inflation, debt]} =
      Convergence.check("GAB", series(-1.0, nil, 75.0), 2025)

    assert ref.status == :not_computed
    assert inflation.status == :no_data
    assert debt.status == :missed
  end

  test "countries outside the CFA unions have no criteria" do
    assert Convergence.check("NGA", series(-4.0, 20.0, 50.0), 2025) == nil
  end

  test "every country has a currency; pegs and zones are consistent" do
    for code <- Currencies.countries() do
      assert %{code: cur} = Currencies.for_country(code)
      assert String.length(cur) == 3
    end

    assert %{code: "XOF", zone: "uemoa", peg: %{anchor: "EUR", rate: 655.957}} =
             Currencies.for_country("SEN")

    assert length(Currencies.for_country("SEN").partners) == 7
    assert %{code: "NGN", zone: nil, peg: nil} = Currencies.for_country("NGA")
    assert %{zone: "cma", peg: %{anchor: "ZAR"}} = Currencies.for_country("NAM")
    assert %{zone: "cma", peg: nil} = Currencies.for_country("ZAF")
    assert Currencies.for_country("FRA") == nil
  end
end
