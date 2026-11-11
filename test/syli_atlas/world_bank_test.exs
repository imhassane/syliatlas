defmodule SyliAtlas.WorldBankTest do
  use ExUnit.Case, async: true
  alias SyliAtlas.WorldBank

  test "creditor shares add up and China is taken out of the bilateral debt" do
    series = %{
      "ppg_debt_usd" => %{"2024" => 100.0},
      "ppg_multilateral_usd" => %{"2024" => 40.0},
      "ppg_bilateral_usd" => %{"2024" => 30.0},
      "ppg_china_usd" => %{"2024" => 20.0},
      "ppg_bonds_usd" => %{"2024" => 25.0},
      "ppg_banks_usd" => %{"2024" => 3.0},
      "ppg_other_private_usd" => %{"2024" => 2.0}
    }

    %{"year" => 2024, "shares" => s} = WorldBank.creditors(series)

    assert s == %{
             "multilateral" => 40.0,
             "china" => 20.0,
             "other_bilateral" => 10.0,
             "bonds" => 25.0,
             "private" => 5.0
           }

    assert WorldBank.creditors(%{}) == nil
  end

  test "the bundled file: every country, latest values with their year, medians" do
    doc = WorldBank.document()
    assert map_size(doc["countries"]) == 54
    assert doc["sources"]["ids"]["license"] == "CC BY 4.0"

    civ = WorldBank.for_country("CIV")
    assert %{"year" => year, "shares" => shares} = civ["creditors"]
    assert year >= 2024
    assert_in_delta Enum.sum(Map.values(shares)), 100, 0.6
    assert %{"year" => _, "value" => _} = civ["latest"]["electricity"]
    assert is_number(doc["medians"]["electricity"])
    # High-income countries are outside the debt statistics.
    refute WorldBank.for_country("SYC")["creditors"]
  end
end
