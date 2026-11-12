defmodule SyliAtlas.Fx.Source do
  @moduledoc """
  An exchange-rate source: fetch without interpreting, parse without
  downloading (as for market sources), so a corrected parser can read the
  stored payloads again.

  `fetch/2` takes a day (`Date`) or `:latest`; `parse/1` returns the day the
  rates describe and the rates, units per US dollar, keyed by upper-case
  ISO 4217 code, as `Decimal`.
  """

  @type response :: %{url: String.t(), status: integer(), body: binary()}

  @callback code() :: String.t()
  @callback name() :: String.t()
  @callback url() :: String.t()
  @callback fetch(Date.t() | :latest, keyword()) :: {:ok, response()} | {:error, term()}
  @callback parse(binary()) :: {:ok, Date.t(), %{String.t() => Decimal.t()}} | {:error, term()}
  @callback parser_version() :: pos_integer()

  @doc "Request options for a source module (Req.Test stubs in tests)."
  def req_options(module) do
    Application.get_env(:syli_atlas, module, []) |> Keyword.get(:req_options, [])
  end
end
