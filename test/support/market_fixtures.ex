defmodule SyliAtlas.MarketFixtures do
  @moduledoc """
  Fictional answers in the shape of the Mansa Markets API, dated from the
  day the test runs (the last business day), so that freshness checks give
  the same result every day. Companies and figures are made up.
  """

  @mansa_ids ~w(nigeria ghana kenya south-africa egypt morocco ivory-coast tanzania zambia uganda
                rwanda malawi zimbabwe vfex botswana namibia mauritius algeria cape-verde eswatini bvmac)

  def last_business_day(today \\ Date.utc_today()) do
    if Date.day_of_week(today) in [6, 7],
      do: last_business_day(Date.add(today, -1)),
      else: today
  end

  def ts(date, time \\ "16:30:00"), do: Date.to_iso8601(date) <> "T" <> time <> "+00:00"

  def day, do: last_business_day()

  def exchanges do
    d = day()

    data =
      for id <- @mansa_ids do
        {value, chg, at} =
          case id do
            "ivory-coast" -> {520.74, 0.1038, ts(d)}
            "nigeria" -> {252_456.74, 1.44, ts(d)}
            "south-africa" -> {112_739.38, 2.67, ts(d)}
            "kenya" -> {239.72, -0.7823, ts(d)}
            "egypt" -> {nil, nil, ts(d)}
            "morocco" -> {nil, nil, ts(d)}
            "malawi" -> {484_395.45, -0.01, ts(Date.add(d, -15))}
            "botswana" -> {11_249.86, 0, ts(d)}
            _ -> {1000.0, 0.5, ts(d)}
          end

        %{
          "id" => id,
          "code" => String.upcase(String.replace(id, "-", "")),
          "name" => id,
          "index_value" => value,
          "index_change_pct" => chg,
          "stocks_count" => 0,
          "last_updated" => at
        }
      end

    %{"success" => true, "data" => data}
  end

  def indices do
    d = day()

    %{
      "success" => true,
      "data" => [
        %{
          "market_id" => "ivory-coast",
          "index_value" => 520.74,
          "index_change_pct" => 0.1038,
          "ytd_change" => "+174.99 (50.61%)",
          "scraped_at" => ts(d)
        },
        %{
          "market_id" => "south-africa",
          "index_value" => 112_739.38,
          "index_change_pct" => 2.67,
          "ytd_change" => "-3,092.90 (2.67%)",
          "scraped_at" => ts(d)
        },
        %{
          "market_id" => "tanzania",
          "index_value" => 1000.0,
          "index_change_pct" => 0.5,
          "ytd_change" => "Vol: 5,749,415 | Deals: 3,941",
          "scraped_at" => ts(d)
        }
      ]
    }
  end

  def stocks("ivory-coast", 0) do
    d = day()

    page(
      [
        stock("ALPT", "Alpha Télécom Sénégal", 4000, -50, -1.2346, 574_160, d),
        stock("BBQ", "Baobab Banque Côte d'Ivoire", 9550, -50, -0.5208, 3244, d),
        stock("CACI", "Cacao Industries Côte d'Ivoire", 8000, 545, 7.3105, 17_058, d),
        stock("DUNE", "Dune Emballages", 1495, nil, nil, nil, d),
        stock("ECLA", "Éclat Énergie", 2200, 900, 69.2, 120, d)
      ],
      "IVORY-COAST",
      "XOF",
      5,
      0
    )
  end

  # Johannesburg: 250 securities, two pages.
  def stocks("south-africa", offset) do
    d = day()
    total = 250

    rows =
      for i <- (offset + 1)..min(offset + 200, total) do
        stock("ZA#{i}", "Company #{i}", 100 + i, 1, 0.5, 1000 + i, d)
      end

    page(rows, "SOUTHAFRICA", "ZAR", total, offset)
  end

  def stocks(_id, offset), do: page([], "X", "XXX", 0, offset)

  defp stock(ticker, name, price, change, pct, volume, d) do
    %{
      "ticker" => ticker,
      "name" => name,
      "price" => price,
      "change" => change,
      "change_pct" => pct,
      "volume" => volume,
      "scraped_at" => ts(d)
    }
  end

  defp page(rows, exchange, currency, total, offset) do
    %{
      "success" => true,
      "data" => rows,
      "meta" => %{"exchange" => exchange, "currency" => currency, "updated_at" => ts(day())},
      "pagination" => %{
        "total" => total,
        "limit" => 200,
        "offset" => offset,
        "has_more" => offset + 200 < total
      }
    }
  end

  def etfs do
    %{
      "success" => true,
      "updated_at" => ts(day(), "17:52:33"),
      "data" => [
        %{
          "symbol" => "GOLDX",
          "canonical_symbol" => "GOLDX",
          "name" => "Fictional Gold ETF",
          "issuer" => "Test Asset Management",
          "isin" => "ZZ0000000001",
          "currency" => "NGN",
          "close" => 78_500,
          "change" => 500,
          "change_percentage" => 0.64,
          "volume" => 47
        },
        %{
          "symbol" => "IDX30",
          "canonical_symbol" => "IDX30",
          "name" => "Fictional Index 30 ETF",
          "issuer" => "Test Funds",
          "isin" => nil,
          "currency" => "NGN",
          "close" => 950,
          "change" => 1,
          "change_percentage" => 0.11,
          "volume" => 30_799
        }
      ]
    }
  end

  def forex do
    %{
      "success" => true,
      "data" => [
        %{
          "pair" => "USD/XOF",
          "base" => "USD",
          "quote" => "XOF",
          "rate" => 600.0,
          "as_of" => ts(day())
        },
        %{
          "pair" => "USD/NGN",
          "base" => "USD",
          "quote" => "NGN",
          "rate" => 1500.0,
          "as_of" => ts(day())
        },
        %{
          "pair" => "USD/ZAR",
          "base" => "USD",
          "quote" => "ZAR",
          "rate" => 16.5,
          "as_of" => ts(day())
        }
      ]
    }
  end

  @doc "Answers the Mansa API stub (Req.Test) like the real service."
  def mansa_plug(conn) do
    params = Plug.Conn.fetch_query_params(conn).query_params
    offset = String.to_integer(params["offset"] || "0")

    body =
      case conn.request_path do
        "/api/v1/markets/exchanges" ->
          exchanges()

        "/api/v1/markets/indices" ->
          indices()

        "/api/v1/markets/exchanges/NGX/etfs" ->
          etfs()

        "/api/v1/markets/forex" ->
          forex()

        "/api/v1/markets/exchanges/" <> rest ->
          stocks(String.replace_suffix(rest, "/stocks", ""), offset)
      end

    Req.Test.json(conn, body)
  end

  @doc "Seeds the reference, runs a full import and publishes, as the evening job does."
  def import! do
    SyliAtlas.Geo.seed_areas!()
    SyliAtlas.Market.seed!()
    Req.Test.stub(SyliAtlas.Market.Sources.Mansa, &mansa_plug/1)
    :ok = SyliAtlas.Workers.MarketImportWorker.run("mansa", SyliAtlas.Market.Sources.Mansa)
    Oban.drain_queue(queue: :market, with_scheduled: true)
    :ok
  end
end
