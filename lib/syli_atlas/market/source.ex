defmodule SyliAtlas.Market.Source do
  @moduledoc """
  What a market data source must do: fetch without interpreting, parse
  without downloading. Keeping the two apart lets a corrected parser read
  months of stored payloads again.

  `fetch/3` returns raw responses; `parse/3` turns one stored body into
  records in a neutral shape, still named with the source's identifiers:

    * `%{type: :index, exchange: ext_id, value:, change_pct:, ytd_pct:, as_of:}`
    * `%{type: :security, exchange: ext_id, ticker:, name:, kind:, close:,
         change:, change_pct:, volume:, currency:, as_of:, issuer:, isin:}`
    * `%{type: :fx, pair:, base:, quote:, rate:, as_of:}`
  """

  @type response :: %{url: String.t(), status: integer(), body: binary()}

  @callback code() :: String.t()
  @callback datasets() :: [String.t()]
  @callback fetch(dataset :: String.t(), exchange_ext_id :: String.t() | nil, opts :: keyword()) ::
              {:ok, [response()]} | {:error, term()}
  @callback parse(dataset :: String.t(), body :: binary(), meta :: map()) ::
              {:ok, [map()]} | {:error, term()}
  @callback parser_version() :: pos_integer()

  @doc "The module implementing a source code."
  def module("mansa"), do: SyliAtlas.Market.Sources.Mansa
end
