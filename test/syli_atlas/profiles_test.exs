defmodule SyliAtlas.ProfilesTest do
  use SyliAtlas.DataCase, async: false
  alias SyliAtlas.Profiles.Queries

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    :ok
  end

  defp decode(json), do: Jason.decode!(json)

  test "a country profile matches the IMF figures" do
    %{"profile" => profile, "period" => period} =
      Queries.area_profile("CIV", 2020, 2025) |> decode()

    assert profile["name"]["fr"] == "Côte d'Ivoire"
    assert profile["default_period"]["real_gdp_change_pct"] == 37.1

    assert profile["default_period"]["rank"] == %{
             "africa" => 7,
             "of_africa" => 53,
             "region" => 3,
             "of_region" => 15
           }

    assert period["changes"]["real_gdp_index"] == 37.1
    assert period["changes"]["public_debt_pct_gdp"] == 10.8
  end

  test "the reference year is a parameter" do
    %{"period" => period} = Queries.area_profile("CIV", 2015, 2025) |> decode()
    assert period["changes"]["real_gdp_index"] == 77.8
  end

  test "regional and continental totals are computed" do
    %{"period" => africa} = Queries.area_profile("africa", 2020, 2025) |> decode()
    %{"period" => west} = Queries.area_profile("west_africa", 2015, 2025) |> decode()

    assert africa["changes"]["real_gdp_index"] == 21.7
    assert west["changes"]["real_gdp_index"] == 29.2
  end

  test "gaps reported by the IMF are kept as nulls" do
    %{"profile" => senegal} = Queries.area_profile("SEN", 2020, 2025) |> decode()
    assert Enum.at(senegal["series"]["real_gdp_growth"], 11) == nil

    assert %{"indicator" => "real_gdp_growth", "years" => [2026, 2027, 2028, 2029, 2030]} in senegal[
             "missing"
           ]
  end

  test "comparison keeps the requested order" do
    codes =
      Queries.compare(["ETH", "CIV", "KEN", "GHA"], 2020, 2025)
      |> decode()
      |> Enum.map(&{&1["code"], &1["real_gdp_change_pct"]})

    assert codes == [{"ETH", 43.1}, {"CIV", 37.1}, {"KEN", 30.7}, {"GHA", 26.1}]
  end

  test "ranking by change, value and region" do
    [first | _] = Queries.ranking("real_gdp_index", 2015, 2025) |> decode()
    assert first["code"] == "ETH"

    west = Queries.ranking("real_gdp_index", 2020, 2025, region: "west_africa") |> decode()
    assert length(west) == 15
    assert Enum.take(west, 3) |> Enum.map(& &1["code"]) == ["CPV", "BEN", "CIV"]
  end

  test "search ignores accents and case" do
    assert [%{"code" => "CIV"}] = Queries.search("COTE") |> decode()
  end

  test "every JSON function stays under the 1.5 ms budget at p95" do
    SyliAtlas.Profiles.QueryStats.reset()

    for stat <- SyliAtlas.Profiles.Benchmark.run(100) do
      assert stat.p95 < SyliAtlas.Profiles.QueryStats.budget_us(),
             "#{stat.name}: p95 #{stat.p95} µs"
    end
  end

  test "map snapshot: one row per country, ranked by GDP in dollars" do
    %{"from" => 2020, "to" => 2025, "countries" => countries} =
      SyliAtlas.Profiles.Queries.map_countries("fr") |> Jason.decode!()

    assert length(countries) == 54
    [first | _] = countries
    assert first["rank"] == 1
    ranked = Enum.filter(countries, & &1["gdp"])
    assert Enum.map(ranked, & &1["gdp"]) == Enum.sort(Enum.map(ranked, & &1["gdp"]), :desc)
    civ = Enum.find(countries, &(&1["code"] == "CIV"))
    assert civ["real_change"] == 37.1
    assert is_list(civ["series"]) and length(civ["series"]) == 16
  end
end
