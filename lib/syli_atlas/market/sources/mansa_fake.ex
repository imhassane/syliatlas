defmodule SyliAtlas.Market.Sources.MansaFake do
  @moduledoc """
  A stand-in for the MansaAPI, for the development environment: same
  endpoints, same JSON shapes, **fictitious figures**, no request to
  mansaapi.com, so development never spends the daily quota of the real
  key (100 calls a day, shared with production).

  Plugged into the Mansa client's Req (`plug:` option) when
  `MANSA_FAKE=true` (config/runtime.exs); refused in the Railway
  environment named `production`. While it is on, `SyliAtlas.Market.fake?/0`
  is true and every credit reads « fictitious data » instead of MansaAPI's.

  The figures are deterministic: the same trading day always gives the
  same answer, and they move from one trading day to the next (two slow
  waves per security), so curves, rises, falls, alerts and the quality
  checks all have something to work on. Names and tickers are invented.
  """
  @behaviour Plug

  import Plug.Conn

  # Mansa's exchange ids (as mapped in SyliAtlas.Market.Reference), currency,
  # index base, securities listed.
  @exchanges [
    {"nigeria", "NGN", 105_000.0, 24},
    {"ghana", "GHS", 6_200.0, 12},
    {"kenya", "KES", 160.0, 16},
    {"south-africa", "ZAR", 98_000.0, 30},
    {"egypt", "EGP", 34_000.0, 20},
    {"morocco", "MAD", 16_500.0, 18},
    {"ivory-coast", "XOF", 330.0, 24},
    {"tanzania", "TZS", 2_100.0, 10},
    {"zambia", "ZMW", 14_000.0, 8},
    {"uganda", "UGX", 1_200.0, 8},
    {"rwanda", "RWF", 150.0, 6},
    {"malawi", "MWK", 300_000.0, 8},
    {"zimbabwe", "ZWG", 220.0, 10},
    {"vfex", "USD", 1_000.0, 6},
    {"botswana", "BWP", 9_800.0, 10},
    {"namibia", "NAD", 1_900.0, 8},
    {"mauritius", "MUR", 2_300.0, 12},
    {"algeria", "DZD", 1_500.0, 5},
    {"cape-verde", "CVE", 1_000.0, 4},
    {"eswatini", "SZL", 500.0, 4},
    {"bvmac", "XAF", 1_000.0, 6}
  ]

  @sectors ~w(Banque Télécom Ciment Brasserie Énergie Assurance Agro Mines Transport Distribution)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn = fetch_query_params(conn)
    day = trading_day(Date.utc_today())

    body =
      case conn.path_info do
        ["api", "v1", "markets", "exchanges"] -> exchanges(day)
        ["api", "v1", "markets", "indices"] -> indices(day)
        ["api", "v1", "markets", "forex"] -> forex(day)
        ["api", "v1", "markets", "exchanges", "NGX", "etfs"] -> etfs(day)
        ["api", "v1", "markets", "exchanges", id, "stocks"] -> stocks(id, day, conn.query_params)
        _ -> nil
      end

    case body do
      nil ->
        conn |> put_resp_content_type("application/json") |> send_resp(404, ~s({"success":false}))

      body ->
        conn |> put_resp_content_type("application/json") |> send_resp(200, JSON.encode!(body))
    end
  end

  # Endpoints ----------------------------------------------------------------

  @doc false
  def exchanges(day) do
    data =
      for {id, _currency, base, count} <- @exchanges do
        {value, pct} = moves(id, base, day)

        %{
          "id" => id,
          "code" => id |> String.replace("-", "") |> String.upcase(),
          "name" => id,
          "index_value" => value,
          "index_change_pct" => pct,
          "stocks_count" => count,
          "last_updated" => stamp(day)
        }
      end

    %{"success" => true, "data" => data}
  end

  @doc false
  def indices(day) do
    first = trading_day(Date.new!(day.year, 1, 1))

    data =
      for {id, _currency, base, _count} <- @exchanges do
        {value, pct} = moves(id, base, day)
        start = level(id, base, first)
        ytd = Float.round((value / start - 1) * 100, 2)

        %{
          "market_id" => id,
          "index_value" => value,
          "index_change_pct" => pct,
          "ytd_change" => "#{sign(value - start)}#{two(abs(value - start))} (#{two(abs(ytd))}%)",
          "scraped_at" => stamp(day)
        }
      end

    %{"success" => true, "data" => data}
  end

  @doc false
  def stocks(id, day, params) do
    case List.keyfind(@exchanges, id, 0) do
      nil ->
        nil

      {_id, currency, _base, count} ->
        limit = int(params["limit"], 200)
        offset = int(params["offset"], 0)

        rows =
          for i <- 1..count//1, i > offset, i <= offset + limit do
            ticker = ticker(id, i)
            {price, pct} = moves(ticker, price_base(ticker), day)
            previous = Float.round(price / (1 + pct / 100), 2)

            %{
              "ticker" => ticker,
              "name" => name(id, i),
              "price" => price,
              "change" => Float.round(price - previous, 2),
              "change_pct" => pct,
              "volume" => volume(ticker, day),
              "scraped_at" => stamp(day)
            }
          end

        %{
          "success" => true,
          "data" => rows,
          "meta" => %{
            "exchange" => id |> String.replace("-", "") |> String.upcase(),
            "currency" => currency,
            "updated_at" => stamp(day)
          },
          "pagination" => %{
            "total" => count,
            "limit" => limit,
            "offset" => offset,
            "has_more" => offset + limit < count
          }
        }
    end
  end

  @doc false
  def etfs(day) do
    data =
      for {symbol, name, base} <- [
            {"DEMOGLD", "ETF Démo Or", 42_000.0},
            {"DEMO30", "ETF Démo Indice 30", 950.0},
            {"DEMOBND", "ETF Démo Obligations", 180.0}
          ] do
        {close, pct} = moves(symbol, base, day)

        %{
          "symbol" => symbol,
          "canonical_symbol" => symbol,
          "name" => name,
          "issuer" => "Démo Gestion",
          "isin" => nil,
          "currency" => "NGN",
          "close" => close,
          "change" => Float.round(close - close / (1 + pct / 100), 2),
          "change_percentage" => pct,
          "volume" => volume(symbol, day)
        }
      end

    %{"success" => true, "updated_at" => stamp(day), "data" => data}
  end

  @doc false
  def forex(day) do
    rates = [
      {"XOF", 600.0},
      {"XAF", 600.0},
      {"NGN", 1_500.0},
      {"GHS", 15.0},
      {"KES", 129.0},
      {"ZAR", 18.0},
      {"EGP", 48.0},
      {"MAD", 9.8},
      {"TZS", 2_600.0},
      {"ZMW", 26.0},
      {"UGX", 3_700.0},
      {"RWF", 1_400.0},
      {"MWK", 1_750.0},
      {"ZWG", 27.0},
      {"BWP", 13.6},
      {"NAD", 18.0},
      {"MUR", 46.0},
      {"DZD", 133.0},
      {"CVE", 101.0},
      {"SZL", 18.0}
    ]

    data =
      for {quote, base} <- rates do
        {rate, _} = moves("USD/" <> quote, base, day, 0.03)

        %{
          "pair" => "USD/" <> quote,
          "base" => "USD",
          "quote" => quote,
          "rate" => rate,
          "as_of" => stamp(day)
        }
      end

    %{"success" => true, "data" => data}
  end

  # Figures ------------------------------------------------------------------

  @doc "The last trading day (Monday to Friday) on or before `date`."
  def trading_day(date) do
    if Date.day_of_week(date) in [6, 7], do: trading_day(Date.add(date, -1)), else: date
  end

  # Level on `day` and change from the previous trading day, in %.
  defp moves(key, base, day, amplitude \\ 0.18) do
    today = level(key, base, day, amplitude)
    before = level(key, base, trading_day(Date.add(day, -1)), amplitude)
    {Float.round(today, 2), Float.round((today / before - 1) * 100, 4)}
  end

  # Two waves with a phase and period of their own per key: smooth, never
  # negative, the same every time it is asked.
  defp level(key, base, day, amplitude \\ 0.18) do
    t = Date.diff(day, ~D[2020-01-01])
    h = :erlang.phash2(key, 1_000_000)
    p1 = 23 + rem(h, 41)
    p2 = 5 + rem(div(h, 41), 7)
    phase = rem(h, 628) / 100

    base *
      (1 + amplitude * :math.sin(t / p1 + phase) + amplitude / 4 * :math.sin(t / p2 + phase * 2))
  end

  defp price_base(ticker), do: 50.0 + :erlang.phash2(ticker, 20_000)

  defp volume(key, day), do: :erlang.phash2({key, day}, 50_000)

  defp ticker(id, i) do
    prefix = id |> String.replace("-", "") |> String.upcase() |> String.slice(0, 2)
    "D#{prefix}#{String.pad_leading(Integer.to_string(i), 2, "0")}"
  end

  defp name(id, i) do
    sector = Enum.at(@sectors, rem(:erlang.phash2({id, i}), length(@sectors)))
    "Démo #{sector} #{i}"
  end

  defp stamp(day), do: Date.to_iso8601(day) <> "T16:30:00+00:00"

  # 1234.5 → "1234.50" (never "1.2345e3").
  defp two(x), do: :erlang.float_to_binary(x * 1.0, decimals: 2)

  defp sign(x) when x < 0, do: "-"
  defp sign(_), do: "+"

  defp int(nil, default), do: default

  defp int(value, default) do
    case Integer.parse(value) do
      {n, ""} when n >= 0 -> n
      _ -> default
    end
  end
end
