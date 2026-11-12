defmodule SyliAtlas.Market.SimulatorTest do
  use SyliAtlas.DataCase, async: false

  alias SyliAtlas.Market.{IndexValue, Simulator}
  alias SyliAtlas.Market.Sources.Mansa
  alias SyliAtlas.Repo

  alias SyliAtlas.MarketFixtures, as: F

  test "a placement follows the index; gain, yearly rate and worst fall" do
    series = [
      {~D[2020-01-02], 100.0},
      {~D[2020-06-01], 150.0},
      {~D[2021-01-04], 120.0},
      {~D[2022-01-03], 200.0}
    ]

    r = Simulator.run(series, ~D[2020-01-01], 1000.0, "XOF", "XOF")
    assert r.start == ~D[2020-01-02] and r.end == ~D[2022-01-03]
    assert_in_delta r.final, 2000.0, 1.0e-9
    assert_in_delta r.gain_pct, 100.0, 1.0e-9
    # Doubled in two years: about 41.4 % a year.
    assert_in_delta r.cagr, 41.4, 0.1
    # From 150 down to 120.
    assert_in_delta r.drawdown, -20.0, 1.0e-9
    assert [%{year: 2020}, %{year: 2021}, %{year: 2022}] = r.years
    assert_in_delta hd(r.years).change, 50.0, 1.0e-9
    assert_in_delta Enum.at(r.years, 1).change, -20.0, 1.0e-9
    assert List.last(r.points) == {~D[2022-01-03], 2000.0}
  end

  test "nothing after the start day gives no result" do
    assert Simulator.run([{~D[2020-01-02], 100.0}], ~D[2021-01-01], 1000.0, "XOF", "XOF") == nil
  end

  test "fixed parities convert exactly, at any date, with no stored rate" do
    assert_in_delta Simulator.rate("EUR", "XOF", ~D[2014-05-05]), 655.957, 1.0e-9
    assert_in_delta Simulator.rate("XAF", "EUR", ~D[2014-05-05]), 1 / 655.957, 1.0e-12
    assert_in_delta Simulator.rate("NAD", "ZAR", ~D[2014-05-05]), 1.0, 1.0e-12
    # A floating currency needs a stored rate of that day.
    assert Simulator.rate("USD", "NGN", ~D[2014-05-05]) == nil

    series = [{~D[2015-01-02], 100.0}, {~D[2016-01-04], 110.0}]
    r = Simulator.run(series, ~D[2015-01-01], 1000.0, "EUR", "XOF")
    assert_in_delta r.final, 1100.0, 1.0e-6
    assert_in_delta r.fx_effect, 0.0, 1.0e-9
  end

  test "the history goes through the pipeline; an exchange is offered with three years" do
    F.import!()
    assert Simulator.available() == []

    F.import_history!()
    brvm = Repo.get_by!(SyliAtlas.Market.Exchange, code: "brvm")

    # The BRVM has four and a half years, the others half a year.
    assert [%{exchange: %{code: "brvm"}, first: ~D[2019-01-02]}] = Simulator.available()

    series = Simulator.series(brvm.id)
    assert hd(series) == {~D[2019-01-02], 100.0}

    # The session imported today is kept as it was, not replaced by history.
    today = Repo.get_by!(IndexValue, exchange_id: brvm.id, trade_date: F.day())
    assert today.change_pct != nil

    others = Simulator.other_starts(series, 1000.0, "XOF", "XOF", [2019, 2020, 2018])
    assert Enum.map(others, & &1.year) == [2019, 2020]

    # Run again: an index with three years is not asked again.
    brvm_payloads = fn ->
      SyliAtlas.Market.RawPayload
      |> where(dataset: "index_history", exchange_code: "brvm")
      |> Repo.aggregate(:count)
    end

    assert brvm_payloads.() == 1
    F.import_history!()
    assert brvm_payloads.() == 1
  end

  test "Mansa's index history is read close by close, marked as history" do
    body =
      Jason.encode!(%{
        "success" => true,
        "data" => %{
          "index_code" => "brvm-ci",
          "points" => [
            %{"date" => "2015-01-02", "close" => 258.21, "volume" => 1},
            %{"date" => "2015-01-05", "close" => "259.4"},
            %{"date" => "not a date", "close" => 1}
          ]
        }
      })

    assert {:ok, [a, b]} = Mansa.parse("index_history", body, %{exchange: "ivory-coast"})
    assert a.exchange == "ivory-coast" and a.history and a.type == :index
    assert Decimal.equal?(a.value, Decimal.new("258.21"))
    assert Decimal.equal?(b.value, Decimal.new("259.4"))
    assert DateTime.to_date(b.as_of) == ~D[2015-01-05]
    assert Mansa.parse("index_history", ~s({"data": []}), %{}) == {:error, :unexpected_shape}
  end
end
