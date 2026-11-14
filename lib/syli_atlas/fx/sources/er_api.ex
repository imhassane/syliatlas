defmodule SyliAtlas.Fx.Sources.ErApi do
  @moduledoc """
  ExchangeRate-API's open endpoint (https://www.exchangerate-api.com/docs/free):
  the latest daily rates, no key. Its terms forbid redistribution and ask
  for a credit wherever its rates are shown, so Syli Atlas never shows
  them: they only check the primary source (a gap above 2% is flagged).
  """
  @behaviour SyliAtlas.Fx.Source

  @endpoint "https://open.er-api.com/v6/latest/USD"

  @impl true
  def code, do: "er_api"
  @impl true
  def name, do: "ExchangeRate-API"
  @impl true
  def url, do: "https://www.exchangerate-api.com"
  @impl true
  def parser_version, do: 1

  @impl true
  def fetch(:latest, opts \\ []) do
    req =
      [
        url: @endpoint,
        retry: :transient,
        max_retries: 2,
        receive_timeout: 20_000,
        decode_body: false
      ]
      |> Keyword.merge(SyliAtlas.Fx.Source.req_options(__MODULE__))
      |> Keyword.merge(opts)

    case Req.get(req) do
      {:ok, %Req.Response{status: status, body: body}} ->
        {:ok, %{url: @endpoint, status: status, body: IO.iodata_to_binary(body)}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  @impl true
  def parse(body) do
    with {:ok, %{"result" => "success", "rates" => rates, "time_last_update_unix" => unix}}
         when is_map(rates) and is_integer(unix) <- Jason.decode(body, floats: :decimals),
         {:ok, at} <- DateTime.from_unix(unix) do
      {:ok, DateTime.to_date(at),
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
