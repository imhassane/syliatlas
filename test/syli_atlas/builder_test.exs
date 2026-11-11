defmodule SyliAtlas.Profiles.BuilderTest do
  use ExUnit.Case, async: true
  alias SyliAtlas.Profiles.Builder

  test "chains growth rates into a volume index" do
    assert Builder.volume_index([5.0, 10.0, 10.0]) |> Enum.map(&Float.round(&1, 2)) == [
             100.0,
             110.0,
             121.0
           ]

    assert Builder.volume_index([1.0, nil, 3.0]) == [100.0, nil, nil]
  end

  test "changes are in points for rates and in percent for levels" do
    values = Enum.map(2015..2030, fn y -> (y - 2014) * 10.0 end)
    assert Builder.change(values, 2015, 2016, :rate) == 10.0
    assert Builder.change(values, 2015, 2016, :level) == 100.0
    assert Builder.change(List.replace_at(values, 0, nil), 2015, 2016, :level) == nil
  end
end
