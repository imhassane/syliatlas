defmodule SyliAtlas.ClimateTest do
  use ExUnit.Case, async: true
  alias SyliAtlas.Climate

  test "every country has the four governance scores, and 29 have B-READY" do
    doc = Climate.document()
    assert doc["covered"] == %{"wgi" => 54, "bready" => 29}
  end

  test "B-READY overall is the mean of the three pillars (Togo 61.52)" do
    togo = Climate.for_country("TGO")
    assert togo["bready"]["overall"]["score"] == 61.52
    assert togo["bready"]["overall"]["of"] == 29
  end

  test "ranks and medians are computed among African countries" do
    entry = Climate.for_country("RWA")
    rq = entry["wgi"]["regulatory_quality"]
    assert rq["of"] == 54
    assert rq["rank"] in 1..54
    assert rq["above"] == rq["score"] > rq["median"]
    assert entry["position"]["tier"] in ~w(above middle below)
  end

  test "a country outside B-READY keeps its governance scores" do
    kenya = Climate.for_country("KEN")
    assert kenya["wgi"]
    refute kenya["bready"]
  end
end
