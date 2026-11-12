defmodule SyliAtlasWeb.VisitorController do
  @moduledoc """
  The visitor's country (from Cloudflare's `CF-IPCountry` header) and the
  currency the site shows by default for it, as for the language. Pages are
  cached for everyone, so the currency menu asks here once per visit; the
  answer is never cached. Nothing else is said: no rate, no address.
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Economy.Currencies

  @euro ~w(AD AT BE CY DE EE ES FI FR GR HR IE IT LT LU LV MC ME MT NL PT SI SK SM VA XK)

  def show(conn, _params) do
    country =
      case get_req_header(conn, "cf-ipcountry") do
        [cc | _] when byte_size(cc) == 2 -> String.upcase(cc)
        _ -> nil
      end

    conn
    |> put_resp_header("cache-control", "private, no-store")
    |> json(%{"country" => country, "currency" => currency_for(country)})
  end

  @doc "The currency shown by default to a visitor from a country (ISO 3166 alpha-2)."
  def currency_for(nil), do: nil
  def currency_for("US"), do: "USD"
  def currency_for("CN"), do: "CNY"
  def currency_for(cc) when cc in @euro, do: "EUR"

  def currency_for(cc) do
    Enum.find_value(Currencies.countries(), fn iso3 ->
      if String.upcase(SyliAtlasWeb.Flags.iso2(iso3) || "") == cc do
        Currencies.for_country(iso3).code
      end
    end)
  end
end
