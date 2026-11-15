defmodule SyliAtlas.Market.SecurityStatsTest do
  use ExUnit.Case, async: true
  alias SyliAtlas.Market.{Profiles, SecurityStats}

  defp sessions(closes_and_volumes) do
    for {{c, v}, i} <- Enum.with_index(closes_and_volumes) do
      %{"date" => Date.to_iso8601(Date.add(~D[2026-11-02], i)), "close" => to_string(c), "volume" => v}
    end
  end

  test "one session: nothing computed beyond the count" do
    s = SecurityStats.compute(sessions([{37.57, 100}]), [], [], %{})
    assert s["sessions"] == 1
    assert s["performance"] == nil and s["high"] == nil and s["volume_ratio"] == nil
  end

  test "performance, against the index over the same days, high and low" do
    ss = sessions([{40.0, 10}, {38.0, 10}, {42.0, 10}])
    index = [["2026-11-01", "100"], ["2026-11-02", "100"], ["2026-11-04", "110"]]
    s = SecurityStats.compute(ss, index, [], %{})
    assert s["performance"] == 5.0
    assert s["index_performance"] == 10.0
    assert s["high"] == 42.0 and s["low"] == 38.0
    assert s["first_date"] == "2026-11-02"
  end

  test "the average volume waits for five previous sessions" do
    four = sessions([{1, 100}, {1, 100}, {1, 100}, {1, 100}, {1, 300}])
    assert SecurityStats.compute(four, [], [], %{})["volume_ratio"] == nil

    five = sessions([{1, 100}, {1, 100}, {1, 100}, {1, 100}, {1, 100}, {1, 250}])
    assert SecurityStats.compute(five, [], [], %{})["volume_ratio"] == 2.5
  end

  test "rank by value traded among the securities traded that day" do
    rows = [
      %{"ticker" => "A", "value" => 10.0, "current" => true},
      %{"ticker" => "B", "value" => 30.0, "current" => true},
      %{"ticker" => "C", "value" => 50.0, "current" => false},
      %{"ticker" => "D", "value" => 0, "current" => true}
    ]

    s = SecurityStats.compute([], [], rows, Enum.at(rows, 0))
    assert s["rank"] == 2 and s["traded"] == 2
    assert SecurityStats.compute([], [], rows, Enum.at(rows, 2))["rank"] == nil
  end

  test "profiles: other listings, peers of the same sector, texts by language" do
    assert [%{"exchange" => "NYSE", "ticker" => "SBSW", "shares_per_receipt" => 4}] =
             Profiles.listings("JSE", "ssw")

    assert "IMP" in Profiles.peers("JSE", "SSW")
    refute "SSW" in Profiles.peers("JSE", "SSW")
    assert Profiles.about("JSE", "SSW", "fr") =~ "platine"
    assert Profiles.sector_name("JSE", "SSW", "pt") == "Mineração de metais preciosos"
    assert Profiles.listings("BRVM", "SNTS") == []
  end
end
