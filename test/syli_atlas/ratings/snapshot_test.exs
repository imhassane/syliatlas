defmodule SyliAtlas.Ratings.SnapshotTest do
  use SyliAtlas.DataCase, async: false
  alias SyliAtlas.Ratings

  setup do
    SyliAtlas.Geo.seed_areas!()
    Ratings.seed!()
    :ok
  end

  test "every country of the continent is either ranked or unrated" do
    doc = Ratings.document()
    assert length(doc["ranking"]) + length(doc["unrated"]) == 54
    assert doc["rated"] == length(doc["ranking"])
    assert Enum.sum(Map.values(doc["counts"])) == doc["rated"]
  end

  test "the ranking is sorted by average, and each entry cites its sources" do
    doc = Ratings.document()
    averages = Enum.map(doc["ranking"], &doc["countries"][&1]["average"])
    assert averages == Enum.sort(averages, :desc)

    for code <- doc["ranking"], agency <- doc["countries"][code]["agencies"] do
      assert agency["source_url"] =~ ~r{^https?://}, "#{code} #{agency["agency"]}"
    end
  end

  test "a newer decision replaces the older one of the same agency" do
    Ratings.put_rating!(%{
      country_code: "CIV",
      agency: "sp",
      rating: "BBB-",
      outlook: "stable",
      action_date: "2099-01-01",
      action_type: "upgrade",
      source_url: "https://example.org/release"
    })

    Ratings.rebuild!()
    civ = Ratings.for_country(Ratings.document(), "CIV")
    sp = Enum.find(civ["agencies"], &(&1["agency"] == "sp"))
    assert sp["rating"] == "BBB-"
    assert hd(Ratings.document()["recent"])["code"] == "CIV"
  end

  test "the stored document matches the code's format" do
    refute Ratings.stale?()
  end
end
