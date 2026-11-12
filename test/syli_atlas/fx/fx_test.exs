defmodule SyliAtlas.FxTest do
  use SyliAtlas.DataCase, async: false
  use Oban.Testing, repo: SyliAtlas.Repo, engine: Oban.Engines.Lite

  alias SyliAtlas.Fx
  alias SyliAtlas.Fx.Rate
  alias SyliAtlas.Fx.Sources.{ErApi, ExchangeApi}
  alias SyliAtlas.FxFixtures, as: F
  alias SyliAtlas.Market.RawPayload

  describe "sources" do
    test "the primary source's body is read as exact decimals, codes upper-cased" do
      body = F.exchange_api_body("2026-11-11", %{"ngn" => "1346.33221129", "bad" => "-1"})
      assert {:ok, ~D[2026-11-11], rates} = ExchangeApi.parse(body)
      assert rates["NGN"] == Decimal.new("1346.33221129")
      refute Map.has_key?(rates, "BAD")
    end

    test "the check source's body gives its update day" do
      assert {:ok, ~D[2026-11-11], rates} =
               ErApi.parse(F.er_api_body(1_794_355_352, %{"ngn" => "1350.42"}))

      assert rates["NGN"] == Decimal.new("1350.42")
      assert {:error, :unexpected_shape} = ErApi.parse(~s({"result":"error"}))
    end

    test "the primary source falls back to the Cloudflare mirror" do
      Req.Test.stub(ExchangeApi, fn conn ->
        if conn.host == "cdn.jsdelivr.net",
          do: Plug.Conn.send_resp(conn, 503, "down"),
          else: Req.Test.text(conn, F.exchange_api_body("2026-11-11", F.now()))
      end)

      assert {:ok, %{url: url, status: 200}} = ExchangeApi.fetch(:latest, [])
      assert url =~ "latest.currency-api.pages.dev"
    end
  end

  describe "import" do
    test "keeps the response raw and stores only the tracked currencies" do
      F.stub_exchange_api()
      assert {:ok, ~D[2026-11-11], n} = Fx.import(ExchangeApi, :latest)

      codes = Repo.all(from r in Rate, select: r.currency)
      assert "NGN" in codes and "EUR" in codes and "CNY" in codes
      # Bitcoin and the old Zimbabwe dollar are not tracked.
      refute "BTC" in codes
      refute "ZWL" in codes
      assert n == length(codes)

      [payload] = Repo.all(RawPayload)
      assert payload.source == "exchange_api" and payload.dataset == "fx"
      assert payload.parsed_at
    end

    test "a day the source cannot serve is an error, nothing stored" do
      F.stub_exchange_api(fail: ["2025-01-01"])
      assert {:error, {:http, 404}} = Fx.import(ExchangeApi, ~D[2025-01-01])
      assert Repo.aggregate(Rate, :count) == 0
    end

    test "missing days are the days without a primary rate" do
      F.stub_exchange_api()
      {:ok, _, _} = Fx.import(ExchangeApi, ~D[2026-11-10])
      missing = Fx.missing_days(3, ~D[2026-11-12])
      assert missing == [~D[2026-11-09], ~D[2026-11-11]]
    end
  end

  describe "published rates" do
    setup do
      %{doc: F.import!()}
    end

    test "pegs come from the anchor and the official parity, not from the source", %{doc: doc} do
      # Euro rate × 655.957, exactly.
      eur = Decimal.new("0.89588492")
      assert Decimal.new(doc["rates"]["XOF"]) == Decimal.mult(eur, Decimal.from_float(655.957))
      assert Decimal.new(doc["rates"]["XAF"]) == Decimal.new(doc["rates"]["XOF"])
      assert_in_delta Fx.per(doc, "XOF", "EUR"), 655.957, 1.0e-9
      # Djibouti franc at its dollar parity even though the source says 178.38.
      assert doc["rates"]["DJF"] == "177.721"
      assert doc["pegs"]["XOF"] == %{"anchor" => "EUR", "rate" => 655.957}
    end

    test "rates against the dollar, the euro and the yuan, and the change over a year", %{
      doc: doc
    } do
      assert doc["as_of"] == "2026-11-11"
      assert doc["year_ago"] == "2025-11-10"
      assert_in_delta Fx.per(doc, "NGN"), 1346.33, 0.01
      assert_in_delta Fx.per(doc, "NGN", "EUR"), 1502.80, 0.01
      assert_in_delta Fx.per(doc, "NGN", "CNY"), 201.72, 0.01
      # The naira gained 6.6% against the dollar, the CFA franc lost 3.4%.
      assert_in_delta Fx.change(doc, "NGN"), 6.59, 0.01
      assert_in_delta Fx.change(doc, "XOF"), -3.43, 0.01
      assert Fx.change(doc, "XOF", "EUR") |> abs() < 1.0e-9
      assert_in_delta Fx.convert(doc, 100_000, "NGN", "USD"), 74.27, 0.01
    end

    test "large moves over the year are flagged for review", %{doc: doc} do
      assert "year_move" in Fx.flags(doc, "LYD")
      assert "year_move" in Fx.flags(doc, "EGP")
      refute "year_move" in Fx.flags(doc, "KES")
      assert Fx.flags(doc, "NGN") == []
    end

    test "a day-to-day jump needs a recent previous day", %{doc: doc} do
      # The only earlier day is a year back: no jump is claimed.
      refute Enum.any?(Map.values(doc["flags"]), &("jump" in &1))
    end

    test "a gap with the check source is flagged" do
      F.stub_er_api(Map.put(F.now(), "ngn", "1500"))
      {:ok, _, _} = Fx.import(ErApi, :latest)
      doc = Fx.publish!()
      assert "gap" in Fx.flags(doc, "NGN")
    end

    test "the pages read the published document", %{doc: doc} do
      assert Fx.latest()["as_of"] == doc["as_of"]
    end
  end

  describe "workers" do
    test "the nightly import stores, checks, publishes and asks for the missing days" do
      F.stub_exchange_api()
      F.stub_er_api()
      assert :ok = perform_job(SyliAtlas.Workers.FxImportWorker, %{})
      assert Fx.latest()["as_of"] == "2026-11-11"
      assert_enqueued(worker: SyliAtlas.Workers.FxBackfillWorker)
    end

    test "the backfill fetches every missing day, skipping failures" do
      F.stub_exchange_api(fail: [Date.utc_today() |> Date.add(-2) |> Date.to_iso8601()])
      assert :ok = perform_job(SyliAtlas.Workers.FxBackfillWorker, %{"days" => 5})
      assert Fx.missing_days(5) == [Date.add(Date.utc_today(), -2)]
    end

    test "a failing primary source makes the nightly job retry" do
      Req.Test.stub(ExchangeApi, &Plug.Conn.send_resp(&1, 500, "boom"))
      F.stub_er_api()
      assert {:error, {:http, 500}} = perform_job(SyliAtlas.Workers.FxImportWorker, %{})
    end
  end
end
