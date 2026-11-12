defmodule SyliAtlas.FxFixtures do
  @moduledoc """
  Real rates (units per US dollar) from fawazahmed0/exchange-api for
  2026-11-11 and 2025-11-10, and from ExchangeRate-API for 2026-11-11,
  served through Req.Test stubs.
  """

  @now %{
    "eur" => "0.89588492",
    "cny" => "6.67429987",
    "ngn" => "1346.33221129",
    "xof" => "587.66198323",
    "xaf" => "587.66198323",
    "kes" => "129.95578447",
    "zar" => "16.51344351",
    "egp" => "53.32167151",
    "ghs" => "11.70750248",
    "etb" => "161.31033369",
    "lyd" => "6.43664604",
    "zwl" => "66709.99681368",
    "btc" => "0.0000098"
  }

  @year_ago %{
    "eur" => "0.86519935",
    "cny" => "7.11953007",
    "ngn" => "1435.1077161",
    "xof" => "567.53357064",
    "xaf" => "567.53357064",
    "kes" => "129.22565321",
    "zar" => "17.28455628",
    "egp" => "47.14858997",
    "ghs" => "10.91984465",
    "etb" => "154.14442007",
    "lyd" => "5.45228272"
  }

  def now, do: @now
  def year_ago, do: @year_ago

  def exchange_api_body(date, rates) do
    inner = rates |> Enum.map(fn {k, v} -> ~s("#{k}":#{v}) end) |> Enum.join(",")
    ~s({"date":"#{date}","usd":{#{inner}}})
  end

  def er_api_body(unix, rates) do
    inner = rates |> Enum.map(fn {k, v} -> ~s("#{String.upcase(k)}":#{v}) end) |> Enum.join(",")

    ~s({"result":"success","time_last_update_unix":#{unix},"base_code":"USD","rates":{"USD":1,#{inner}}})
  end

  @doc """
  Stubs the primary source: `latest` answers 2026-11-11, dated requests
  answer their own day with the year-ago rates (enough for the comparison),
  except the days listed in `fail`.
  """
  def stub_exchange_api(opts \\ []) do
    fail = Keyword.get(opts, :fail, [])

    Req.Test.stub(SyliAtlas.Fx.Sources.ExchangeApi, fn conn ->
      tag =
        case conn.host do
          "cdn.jsdelivr.net" -> conn.path_info |> Enum.at(2) |> String.split("@") |> List.last()
          host -> host |> String.split(".") |> List.first()
        end

      cond do
        tag in fail ->
          Plug.Conn.send_resp(conn, 404, "not found")

        tag == "latest" ->
          Req.Test.text(conn, exchange_api_body("2026-11-11", @now))

        true ->
          Req.Test.text(conn, exchange_api_body(tag, @year_ago))
      end
    end)
  end

  def stub_er_api(rates \\ @now) do
    Req.Test.stub(SyliAtlas.Fx.Sources.ErApi, fn conn ->
      Req.Test.text(conn, er_api_body(1_794_355_352, Map.delete(rates, "zwl")))
    end)
  end

  @doc "Imports today and the day a year earlier, then publishes."
  def import! do
    stub_exchange_api()
    stub_er_api()
    {:ok, _, _} = SyliAtlas.Fx.import(SyliAtlas.Fx.primary(), :latest)
    {:ok, _, _} = SyliAtlas.Fx.import(SyliAtlas.Fx.primary(), ~D[2025-11-10])
    {:ok, _, _} = SyliAtlas.Fx.import(SyliAtlas.Fx.shadow(), :latest)
    SyliAtlas.Fx.publish!()
  end
end
