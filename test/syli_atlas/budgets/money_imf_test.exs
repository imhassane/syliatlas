defmodule SyliAtlas.Budgets.MoneyImfTest do
  use ExUnit.Case, async: true

  alias SyliAtlas.Budgets.{Imf, Money}

  test "short amounts, as the pages write them" do
    assert Money.short(6_087_700_000.0, "EUR", "fr") == "6,09 Md €"
    assert Money.short(233_000_000, "EUR", "fr") == "233 M €"
    assert Money.short(Decimal.new("67925870000000"), "GNF", "fr") == "67 926 Md GNF"
    assert Money.short(4_420_000_000, "USD", "en") == "4.42 bn $"
    assert Money.short(-620_424_000_000, "XOF", "fr") == "−620 Md XOF"
    assert Money.short(nil, "XOF", "fr") == "—"
  end

  test "conversion goes through the dollar rates, fixed pegs included" do
    fx = %{"rates" => %{"EUR" => "0.86", "XOF" => "564.12302"}}
    assert_in_delta Money.convert(655_957.0, "XOF", "EUR", fx), 1000.0, 0.5
    assert Money.convert(10, "XOF", "XOF", fx) == 10.0
    assert Money.convert(10, "XOF", "ZZZ", fx) == nil
    assert Money.default_currency("fr") == "EUR"
    assert Money.default_currency("pt") == "USD"
  end

  test "the bundled IMF file covers the 54 countries" do
    doc = Imf.document()
    assert map_size(doc["countries"]) == 54
    assert is_number(Imf.at(Imf.for_country("ZAF"), "expenditure", 2026))
    assert Imf.at(nil, "revenue", 2026) == nil
  end

  test "refreshing reads both IMF series and keeps 2015–2030" do
    Req.Test.stub(Imf, fn
      %{request_path: "/external/datamapper/api/v1/indicators"} = conn ->
        Req.Test.json(conn, %{
          "indicators" => %{"GGR_G01_GDP_PT" => %{"source" => "Fiscal Monitor (April 2027)"}}
        })

      %{request_path: "/external/datamapper/api/v1/" <> code} = conn ->
        Req.Test.json(conn, %{
          "values" => %{code => %{"MLI" => %{"2014" => 1.0, "2026" => 18.979, "2031" => 5.0}}}
        })
    end)

    assert {:ok, doc} = Imf.fetch(["MLI", "SEN"])
    assert doc["source"]["label"] == "Fiscal Monitor (April 2027)"
    assert doc["countries"]["MLI"]["revenue"] == %{"2026" => 18.98}
    assert doc["countries"]["SEN"]["expenditure"] == %{}
  end
end
