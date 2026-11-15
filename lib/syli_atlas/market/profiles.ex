defmodule SyliAtlas.Market.Profiles do
  @moduledoc """
  Facts about listed companies that the market source does not give, kept by
  hand in `priv/data/security_profiles.json`: the other places a security
  trades (SSW at the JSE is SBSW at the NYSE), its sector, its ISIN and two
  sentences on its business.

  Read at compile time: a change of the file ships with a release.
  """

  @path Path.join([__DIR__, "../../../priv/data/security_profiles.json"])
  @external_resource @path
  @data @path |> File.read!() |> Jason.decode!()

  @doc "The entry of a security (`exchange` code, ticker in any case), or an empty map."
  def get(exchange, ticker) when is_binary(exchange) and is_binary(ticker) do
    Map.get(@data["securities"], key(exchange, ticker), %{})
  end

  @doc "The other listings of a security: `[%{\"exchange\", \"ticker\", \"kind\", \"shares_per_receipt\"}]`."
  def listings(exchange, ticker), do: get(exchange, ticker)["listings"] || []

  @doc "Tickers of the same exchange and sector, the security itself excluded."
  def peers(exchange, ticker) do
    case get(exchange, ticker)["sector"] do
      nil ->
        []

      sector ->
        prefix = String.upcase(exchange) <> "/"
        own = key(exchange, ticker)

        for {k, v} <- @data["securities"],
            k != own,
            String.starts_with?(k, prefix),
            v["sector"] == sector,
            do: String.replace_prefix(k, prefix, "")
    end
    |> Enum.sort()
  end

  @doc "The sector's name in `locale`, or nil."
  def sector_name(exchange, ticker, locale) do
    with sector when is_binary(sector) <- get(exchange, ticker)["sector"],
         names when is_map(names) <- @data["sectors"][sector] do
      SyliAtlas.Locales.pick(names, locale)
    else
      _ -> nil
    end
  end

  @doc "Two sentences on the business, in `locale`, or nil."
  def about(exchange, ticker, locale) do
    case get(exchange, ticker)["about"] do
      %{} = texts -> SyliAtlas.Locales.pick(texts, locale)
      _ -> nil
    end
  end

  defp key(exchange, ticker), do: String.upcase(exchange) <> "/" <> String.upcase(ticker)
end
