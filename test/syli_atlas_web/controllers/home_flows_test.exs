defmodule SyliAtlasWeb.HomeFlowsTest do
  use SyliAtlasWeb.ConnCase, async: false

  alias SyliAtlasWeb.TradeFlowComponents, as: Flows

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    :ok
  end

  test "the home page shows Africa's trade flows, both drawings, the table and the link" do
    doc = build_conn() |> get("/fr") |> html_response(200) |> LazyHTML.from_document()

    for sel <-
          ~w(#commerce-afrique #flows-answer #flows-wide #flows-narrow #flows-data #flows-link) do
      assert LazyHTML.query(doc, sel) |> Enum.count() == 1, "missing #{sel}"
    end

    assert doc |> LazyHTML.query("#flows-link") |> LazyHTML.attribute("href") == [
             "/fr/afrique/commerce"
           ]

    assert doc |> LazyHTML.query("#flows-data tbody tr") |> Enum.count() == 14
    text = doc |> LazyHTML.query("#flows-answer") |> LazyHTML.text()
    assert text =~ "« Pétrole, gaz et charbon » (31"
    assert text =~ "Il manque 36,4 Md$"
  end

  test "a deficit is a ribbon on the left, a surplus on the right; shares use their own side" do
    deficit =
      Flows.flows(%{
        "exports" => 80,
        "imports" => 100,
        "families" => %{
          "exports" => %{"energy" => 60, "farm" => 20},
          "imports" => %{"food" => 70, "machines" => 30}
        }
      })

    assert List.last(deficit.left).gap and List.last(deficit.left).value == 20
    refute Enum.any?(deficit.right, & &1.gap)

    surplus =
      Flows.flows(%{
        "exports" => 120,
        "imports" => 100,
        "families" => %{
          "exports" => %{"energy" => 100, "farm" => 20},
          "imports" => %{"food" => 70, "machines" => 30}
        }
      })

    assert List.last(surplus.right).gap and List.last(surplus.right).value == 20
    assert Flows.sentence(surplus, 2024, "en") =~ "are left over"
    assert Flows.sentence(surplus, 2024, "en") =~ "“Oil, gas and coal” (83"
  end
end
