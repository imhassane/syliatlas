defmodule SyliAtlas.Fx.Sources.ExchangeApi do
  @moduledoc """
  fawazahmed0/exchange-api (https://github.com/fawazahmed0/exchange-api):
  daily rates for 200+ currencies, no key, no quota, history by date,
  released under CC0. The primary source of Syli Atlas rates.

  The project names no upstream source and gives no guarantee, so its
  figures are checked against a second source (`ErApi`) and fixed pegs are
  never taken from it (`SyliAtlas.Fx`). As its README asks, every request
  falls back from jsDelivr to the Cloudflare mirror.
  """
  @behaviour SyliAtlas.Fx.Source

  @impl true
  def code, do: "exchange_api"
  @impl true
  def name, do: "fawazahmed0/exchange-api"
  @impl true
  def url, do: "https://github.com/fawazahmed0/exchange-api"

  @doc "The first day the source publishes by date (its npm releases start there)."
  def first_day, do: ~D[2024-03-02]
  @impl true
  def parser_version, do: 1

  @impl true
  def fetch(day, opts \\ []) do
    tag = tag(day)

    urls = [
      "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@#{tag}/v1/currencies/usd.min.json",
      "https://#{tag}.currency-api.pages.dev/v1/currencies/usd.min.json"
    ]

    Enum.reduce_while(urls, {:error, :no_response}, fn url, _acc ->
      case get(url, opts) do
        {:ok, %{status: 200} = response} -> {:halt, {:ok, response}}
        {:ok, %{status: status}} -> {:cont, {:error, {:http, status}}}
        {:error, reason} -> {:cont, {:error, reason}}
      end
    end)
  end

  defp tag(:latest), do: "latest"
  defp tag(%Date{} = day), do: Date.to_iso8601(day)

  defp get(url, opts) do
    req =
      [url: url, retry: :transient, max_retries: 2, receive_timeout: 20_000, decode_body: false]
      |> Keyword.merge(SyliAtlas.Fx.Source.req_options(__MODULE__))
      |> Keyword.merge(opts)

    case Req.get(req) do
      {:ok, %Req.Response{status: status, body: body}} ->
        {:ok, %{url: url, status: status, body: IO.iodata_to_binary(body)}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  @impl true
  def parse(body) do
    with {:ok, %{"date" => date, "usd" => rates}} when is_map(rates) <-
           Jason.decode(body, floats: :decimals),
         {:ok, day} <- Date.from_iso8601(date) do
      {:ok, day,
       for {code, rate} <- rates, decimal = to_decimal(rate), into: %{} do
         {String.upcase(code), decimal}
       end}
    else
      {:ok, _} -> {:error, :unexpected_shape}
      {:error, _} = error -> error
    end
  end

  defp to_decimal(%Decimal{} = d), do: if(Decimal.gt?(d, 0), do: d)
  defp to_decimal(n) when is_integer(n) and n > 0, do: Decimal.new(n)
  defp to_decimal(_), do: nil
end
