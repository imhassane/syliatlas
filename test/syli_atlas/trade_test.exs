defmodule SyliAtlas.TradeTest do
  use ExUnit.Case, async: true
  alias SyliAtlas.Trade

  test "concentration tiers" do
    assert Trade.tier(85.8) == "high"
    assert Trade.tier(35.0) == "medium"
    assert Trade.tier(19.8) == "low"
    assert Trade.tier(nil) == nil
  end

  test "the bundled BACI file: every country, labelled chapters and partners" do
    doc = Trade.document()
    assert map_size(doc["countries"]) == 54
    assert doc["source"]["license"] == "Licence Ouverte Etalab 2.0"

    for {_code, c} <- doc["countries"] do
      assert length(c["top_exports"]) <= 5
      for t <- c["top_exports"], do: assert(doc["chapters"][t["chapter"]]["fr"])
      for t <- c["top_clients"], do: assert(doc["partners"][t["code"]]["fr"])
      assert c["concentration"] in ~w(high medium low)
    end

    assert hd(Trade.for_country("NGA")["top_exports"])["chapter"] == "27"
    assert is_number(doc["medians"]["africa_share_exports"])
  end
end
