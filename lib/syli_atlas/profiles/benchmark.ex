defmodule SyliAtlas.Profiles.Benchmark do
  @moduledoc "Replays every JSON function with typical inputs; used after imports."
  alias SyliAtlas.Profiles.Queries

  def run(times \\ 200) do
    for _ <- 1..times do
      Queries.area_profile("CIV", 2020, 2025)
      Queries.area_profile("west_africa", 2015, 2030)
      Queries.compare(["CIV", "GHA", "KEN", "ETH"], 2020, 2025)
      Queries.ranking("real_gdp_index", 2020, 2025)
      Queries.ranking("inflation", 2015, 2025, region: "west_africa", mode: "value")
      Queries.search("cote")
      Queries.map_countries("fr")
    end

    SyliAtlas.Profiles.QueryStats.summary()
  end
end
