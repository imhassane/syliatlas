defmodule SyliAtlas.Imports.ImfParserTest do
  use ExUnit.Case, async: true
  alias SyliAtlas.Imports.ImfParser
  doctest ImfParser

  test "reads month and year from the edition label" do
    assert ImfParser.edition_code("World Economic Outlook (April 2027)") == {:ok, "2027-04"}
    assert ImfParser.edition_code("something else") == {:error, :unrecognized_label}
  end

  test "maps IMF codes to areas and keeps 2015-2030 only" do
    payload = %{
      "values" => %{"NGDP_RPCH" => %{"CIV" => %{"2014" => 8.0, "2020" => 0.7, "2031" => 6.0}}}
    }

    rows = ImfParser.rows(payload, %{"CIV" => "CIV"})

    assert length(rows) == 16
    assert %{area_code: "CIV", indicator: "real_gdp_growth", year: 2020, value: 0.7} in rows
    refute Enum.any?(rows, &(&1.year in [2014, 2031]))
  end
end
