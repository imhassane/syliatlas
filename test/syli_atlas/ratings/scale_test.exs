defmodule SyliAtlas.Ratings.ScaleTest do
  use ExUnit.Case, async: true
  alias SyliAtlas.Ratings.Scale

  test "S&P, Fitch and Moody's symbols share one scale" do
    assert Scale.score("AAA") == 22
    assert Scale.score("Aaa") == 22
    assert Scale.score("BBB-") == 13
    assert Scale.score("Baa3") == 13
    assert Scale.score("BB") == 11
    assert Scale.score("B") == 8
    assert Scale.score("Caa1") == 6
    assert Scale.score("SD") == 1
    assert Scale.score("RD") == 1
    assert Scale.score("nonsense") == nil
  end

  test "typographic minus signs are normalized and displayed" do
    assert Scale.normalize("BBB−") == "BBB-"
    assert Scale.display("BB-") == "BB−"
  end

  test "averages round half up to a label" do
    assert Scale.round_score(12.5) == 13
    assert Scale.label(12.5) == "BBB−"
    assert Scale.label(8.33) == "B"
  end

  test "bands follow the agencies' categories" do
    assert Scale.band(13.0) == "investment"
    assert Scale.band(12.5) == "investment"
    assert Scale.band(11.0) == "speculative"
    assert Scale.band(8.0) == "highly_speculative"
    assert Scale.band(5.0) == "substantial_risk"
    assert Scale.band(1.0) == "default"
  end

  test "distance to investment grade in notches" do
    assert Scale.notches_to_investment(11.0) == 2
    assert Scale.notches_to_investment(14.0) == -1
  end
end
