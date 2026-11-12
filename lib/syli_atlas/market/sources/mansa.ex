defmodule SyliAtlas.Market.Sources.Mansa do
  @moduledoc """
  Mansa Markets (mansaapi.com), an aggregator of African market data.
  The free tier gives 100 requests a day for personal use; every call goes
  through the quota in `SyliAtlas.Market.Ingestion`.

  Datasets and their cost on a normal day: `exchanges` (1, every index),
  `indices` (1, adds the change since 1 January), `stocks` (one per 200
  securities of an exchange, 24 for all 21), `etfs` (1, the NGX's) and
  `forex` (1). The key is read from the `STOCK_EXCHANGE_API_KEY`
  environment variable.

  `index_history` (one call per index, run once by
  `SyliAtlas.Workers.IndexHistoryWorker`) brings the past closes of the
  main indices that Mansa keeps (`/indices/{code}/history`), for the
  simulator.
  """
  @behaviour SyliAtlas.Market.Source
  alias SyliAtlas.Market.Ingestion

  @base "https://mansaapi.com/api/v1/markets"
  @page 200

  @impl true
  def code, do: "mansa"

  @impl true
  def datasets, do: ~w(exchanges indices stocks etfs forex index_history)

  # Our exchanges' Mansa ids → the code of their main index in
  # `/indices/{code}/history` (codes named in Mansa's documentation).
  @history_codes %{
    "ivory-coast" => "brvm-ci",
    "nigeria" => "ngx-asi",
    "south-africa" => "jse-asi",
    "ghana" => "gse-ci",
    "egypt" => "egx-30",
    "morocco" => "masi",
    "namibia" => "nsx-oi"
  }

  @doc "Mansa exchange ids whose main index has a history, with the index code."
  def history_codes, do: @history_codes

  @impl true
  def parser_version, do: 1

  # The development stand-in (`MansaFake`) needs no key.
  def configured?, do: SyliAtlas.Market.fake?() or api_key() not in [nil, ""]

  @impl true
  def fetch("stocks", ext_id, opts) when is_binary(ext_id), do: fetch_pages(ext_id, 0, [], opts)
  def fetch("exchanges", _ext, opts), do: fetch_one("/exchanges", opts)
  def fetch("indices", _ext, opts), do: fetch_one("/indices", opts)
  def fetch("etfs", _ext, opts), do: fetch_one("/exchanges/NGX/etfs", opts)
  def fetch("forex", _ext, opts), do: fetch_one("/forex", opts)

  def fetch("index_history", ext_id, opts) do
    case Map.fetch(@history_codes, ext_id) do
      {:ok, index} ->
        with {:ok, response} <- get("/indices/#{index}/history", [from: "2010-01-01"], opts),
             do: {:ok, [response]}

      :error ->
        {:error, :no_history}
    end
  end

  defp fetch_one(path, opts) do
    with {:ok, response} <- get(path, [], opts), do: {:ok, [response]}
  end

  defp fetch_pages(ext_id, offset, acc, opts) do
    path = "/exchanges/#{ext_id}/stocks"

    with {:ok, response} <- get(path, [limit: @page, offset: offset], opts) do
      acc = [response | acc]

      case Jason.decode(response.body) do
        {:ok, %{"pagination" => %{"has_more" => true, "total" => total}}}
        when offset + @page < total ->
          fetch_pages(ext_id, offset + @page, acc, opts)

        _ ->
          {:ok, Enum.reverse(acc)}
      end
    end
  end

  defp get(path, params, opts) do
    config = Application.get_env(:syli_atlas, __MODULE__, [])

    Ingestion.call(code(), fn ->
      [
        base_url: Keyword.get(config, :base_url, @base),
        url: path,
        params: params,
        headers: [{"x-api-key", api_key() || ""}],
        decode_body: false,
        # Never retry a 429: Mansa's limit is daily, every retry is a lost call.
        retry: &retry?/2,
        max_retries: 2,
        receive_timeout: 30_000
      ]
      |> Keyword.merge(Keyword.get(config, :req_options, []))
      |> Keyword.merge(Keyword.get(opts, :req_options, []))
      |> Req.request()
      |> case do
        {:ok, %Req.Response{status: 200, body: body} = r} ->
          {:ok, %{url: url_of(r, path, params), status: 200, body: body}}

        {:ok, %Req.Response{status: 429, body: body}} ->
          {:error, {:daily_limit, reset_at(body)}}

        {:ok, %Req.Response{status: status}} ->
          {:error, {:http_status, status, path}}

        {:error, exception} ->
          {:error, {Exception.message(exception), path}}
      end
    end)
  end

  defp retry?(_request, %Req.Response{status: status}), do: status in [408, 500, 502, 503, 504]
  defp retry?(_request, _exception), do: true

  # "reset_at" of Mansa's 429 answer, else the next midnight UTC.
  defp reset_at(body) do
    with {:ok, %{"error" => %{"reset_at" => text}}} <- Jason.decode(body || ""),
         {:ok, dt, _} <- DateTime.from_iso8601(text) do
      DateTime.truncate(dt, :second)
    else
      _ ->
        Date.utc_today()
        |> Date.add(1)
        |> DateTime.new!(~T[00:00:00])
        |> DateTime.truncate(:second)
    end
  end

  defp url_of(_r, path, []), do: @base <> path
  defp url_of(_r, path, params), do: @base <> path <> "?" <> URI.encode_query(params)

  defp api_key, do: Application.get_env(:syli_atlas, __MODULE__, [])[:api_key]

  # Parsing ---------------------------------------------------------------

  @impl true
  def parse("index_history", body, meta) do
    case Jason.decode(body) do
      {:ok, %{"data" => %{"points" => points}}} when is_list(points) ->
        {:ok,
         for p <- points,
             {:ok, day} <- [Date.from_iso8601(to_string(p["date"] || p["trade_date"]))],
             %Decimal{} = close <- [history_close(p["close"] || p["value"])] do
           %{
             type: :index,
             exchange: meta.exchange,
             value: close,
             change_pct: nil,
             ytd_pct: nil,
             as_of: DateTime.new!(day, ~T[16:00:00]),
             history: true
           }
         end}

      {:ok, _} ->
        {:error, :unexpected_shape}

      {:error, _} ->
        {:error, :invalid_json}
    end
  end

  def parse(dataset, body, meta) do
    case Jason.decode(body) do
      {:ok, %{"data" => data} = doc} when is_list(data) ->
        {:ok, records(dataset, data, doc, meta)}

      {:ok, _} ->
        {:error, :unexpected_shape}

      {:error, _} ->
        {:error, :invalid_json}
    end
  end

  defp history_close(n) when is_integer(n) and n > 0, do: Decimal.new(n)
  defp history_close(n) when is_float(n) and n > 0, do: Decimal.from_float(n)

  defp history_close(s) when is_binary(s) do
    case Decimal.parse(String.trim(s)) do
      {d, ""} -> if Decimal.gt?(d, 0), do: d
      _ -> nil
    end
  end

  defp history_close(_), do: nil

  defp records("exchanges", data, _doc, _meta) do
    for e <- data, is_binary(e["id"]) do
      %{
        type: :index,
        exchange: e["id"],
        value: e["index_value"],
        change_pct: e["index_change_pct"],
        ytd_pct: nil,
        as_of: datetime(e["last_updated"]),
        listed: e["stocks_count"]
      }
    end
  end

  defp records("indices", data, _doc, _meta) do
    for i <- data, is_binary(i["market_id"]) do
      %{
        type: :index,
        exchange: i["market_id"],
        value: i["index_value"],
        change_pct: i["index_change_pct"],
        ytd_pct: ytd(i["ytd_change"]),
        as_of: datetime(i["scraped_at"])
      }
    end
  end

  defp records("stocks", data, doc, meta) do
    currency = get_in(doc, ["meta", "currency"])

    for s <- data, is_binary(s["ticker"]) do
      %{
        type: :security,
        exchange: meta[:exchange],
        ticker: s["ticker"],
        name: s["name"] || s["ticker"],
        kind: "equity",
        close: s["price"],
        change: s["change"],
        change_pct: s["change_pct"],
        volume: integer(s["volume"]),
        currency: s["currency"] || currency,
        as_of: datetime(s["scraped_at"] || get_in(doc, ["meta", "updated_at"])),
        issuer: nil,
        isin: nil
      }
    end
  end

  defp records("etfs", data, doc, _meta) do
    as_of = datetime(doc["updated_at"])

    for e <- data, is_binary(e["symbol"]) do
      %{
        type: :security,
        exchange: "nigeria",
        ticker: e["canonical_symbol"] || e["symbol"],
        name: e["name"] || e["symbol"],
        kind: "etf",
        close: e["close"],
        change: e["change"],
        change_pct: e["change_percentage"],
        volume: integer(e["volume"]),
        currency: e["currency"] || "NGN",
        as_of: as_of,
        issuer: e["issuer"],
        isin: e["isin"]
      }
    end
  end

  defp records("forex", data, _doc, _meta) do
    for f <- data, is_binary(f["pair"]), is_number(f["rate"]) do
      %{
        type: :fx,
        pair: f["pair"],
        base: f["base"],
        quote: f["quote"],
        rate: f["rate"],
        as_of: datetime(f["as_of"])
      }
    end
  end

  @doc false
  # "+174.99 (50.61%)" → 50.61, "-3,092.90 (2.67%)" → -2.67; anything else → nil.
  def ytd(text) when is_binary(text) do
    case Regex.run(~r/^\s*([+-])?[\d,.]+\s*\(\s*-?([\d.]+)\s*%\s*\)\s*$/, text) do
      [_, "-", pct] -> -String.to_float(normalize(pct))
      [_, _, pct] -> String.to_float(normalize(pct))
      _ -> nil
    end
  end

  def ytd(_), do: nil

  defp normalize(pct), do: if(String.contains?(pct, "."), do: pct, else: pct <> ".0")

  defp integer(n) when is_integer(n), do: n
  defp integer(n) when is_float(n), do: round(n)
  defp integer(_), do: nil

  defp datetime(nil), do: nil

  defp datetime(text) when is_binary(text) do
    case DateTime.from_iso8601(text) do
      {:ok, dt, _} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end
end
