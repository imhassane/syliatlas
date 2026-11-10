defmodule SyliAtlas.Market.MansaTest do
  use ExUnit.Case, async: true
  alias SyliAtlas.Market.Sources.Mansa
  alias SyliAtlas.MarketFixtures, as: F

  test "reads the change since 1 January, signed, and nothing else" do
    assert Mansa.ytd("+174.99 (50.61%)") == 50.61
    assert Mansa.ytd("-3,092.90 (2.67%)") == -2.67
    assert Mansa.ytd("-1,272.95 (4.91%)") == -4.91
    assert Mansa.ytd("Vol: 5,749,415 | Deals: 3,941") == nil
    assert Mansa.ytd(nil) == nil
  end

  test "parses indices, keeping a missing value as nil" do
    {:ok, records} = Mansa.parse("exchanges", Jason.encode!(F.exchanges()), %{})
    assert length(records) == 21
    egypt = Enum.find(records, &(&1.exchange == "egypt"))
    assert egypt.value == nil and egypt.type == :index
    brvm = Enum.find(records, &(&1.exchange == "ivory-coast"))
    assert brvm.value == 520.74
    assert %DateTime{} = brvm.as_of
  end

  test "parses a page of securities with the exchange given by the caller" do
    {:ok, records} =
      Mansa.parse("stocks", Jason.encode!(F.stocks("ivory-coast", 0)), %{exchange: "ivory-coast"})

    alpt = Enum.find(records, &(&1.ticker == "ALPT"))
    assert alpt.exchange == "ivory-coast" and alpt.currency == "XOF" and alpt.kind == "equity"
    assert alpt.close == 4000 and alpt.volume == 574_160
  end

  test "parses funds and exchange rates" do
    {:ok, etfs} = Mansa.parse("etfs", Jason.encode!(F.etfs()), %{})
    assert Enum.all?(etfs, &(&1.kind == "etf" and &1.exchange == "nigeria"))
    {:ok, fx} = Mansa.parse("forex", Jason.encode!(F.forex()), %{})
    assert Enum.find(fx, &(&1.pair == "USD/XOF")).rate == 600.0
  end

  test "refuses a body that is not the expected shape" do
    assert {:error, :invalid_json} = Mansa.parse("stocks", "<html>", %{})
    assert {:error, :unexpected_shape} = Mansa.parse("stocks", ~s({"error":"x"}), %{})
  end
end
