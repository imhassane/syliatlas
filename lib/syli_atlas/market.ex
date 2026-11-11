defmodule SyliAtlas.Market do
  @moduledoc """
  Stock exchanges, listed securities and their daily closes. Pages read
  the documents built by `SyliAtlas.Market.Snapshots`; the pipeline that
  fills them is in `SyliAtlas.Market.Pipeline` and the Oban workers.

  The pages are public when the licence of an active source allows it
  (MansaAPI's does, with its credit), or while the market section is in
  preview (the `:preview` option, `MARKET_PREVIEW=true` in production),
  for a source whose licence does not.
  """
  import Ecto.Query
  alias SyliAtlas.Repo
  alias SyliAtlas.Market.{Catalog, EodPrice, Reference, Snapshots}

  @doc "May the market pages be shown to the public?"
  def public?(sources \\ Catalog.all()) do
    Keyword.get(config(), :preview, false) or
      Enum.any?(sources, &(&1.status == "active" and &1.licence.display_public))
  end

  def config, do: Application.get_env(:syli_atlas, __MODULE__, [])

  @doc """
  Whether the market figures come from `SyliAtlas.Market.Sources.MansaFake`
  (development, `MANSA_FAKE=true`): every credit then says they are
  fictitious.
  """
  def fake?, do: Keyword.get(config(), :fake, false)

  def seed!, do: Reference.seed!()

  def overview, do: Snapshots.read("market:overview")
  def exchange(code) when is_binary(code), do: Snapshots.read("market:exchange:" <> code)
  def etfs, do: Snapshots.read("market:etfs")
  def fx, do: Snapshots.read("market:fx")

  @doc "A security's row in its exchange's document, with the document."
  def security(exchange_code, ticker) do
    with %{} = doc <- exchange(exchange_code),
         %{} = row <- Enum.find(doc["securities"], &(String.downcase(&1["ticker"]) == ticker)) do
      {doc, row}
    else
      _ -> nil
    end
  end

  @doc "Closes of a security, oldest first, the last `limit` sessions."
  def security_history(security_id, limit \\ 260) do
    Repo.all(
      from p in EodPrice,
        where: p.security_id == ^security_id,
        order_by: [desc: p.trade_date],
        limit: ^limit,
        select: {p.trade_date, p.close}
    )
    |> Enum.reverse()
    |> Enum.map(fn {d, c} -> [Date.to_iso8601(d), Decimal.to_string(c, :normal)] end)
  end

  @doc "Exchanges serving a country, from the overview, with their busiest local shares."
  def for_country(area_code, overview \\ overview())

  def for_country(_area_code, nil), do: []

  def for_country(area_code, %{"exchanges" => exchanges}) do
    for x <- exchanges, area_code in x["exchange"]["countries"] do
      regional? = length(x["exchange"]["countries"]) > 1
      top = if regional?, do: Enum.filter(x["top"], &(&1["country"] == area_code)), else: x["top"]
      Map.merge(x, %{"top" => top, "regional" => regional?})
    end
  end

  @doc "Converts an amount in `currency` to US dollars with the stored rates, or nil."
  def to_usd(nil, _currency, _fx), do: nil
  def to_usd(amount, "USD", _fx), do: amount
  def to_usd(_amount, _currency, nil), do: nil

  def to_usd(amount, currency, %{"rates" => rates}) do
    case rates["USD/" <> currency] do
      rate when is_number(rate) and rate > 0 -> amount / rate
      _ -> nil
    end
  end

  @version_key {__MODULE__, :data_version}

  @doc "A short identifier of the market data online, kept in memory (see `SyliAtlas.Profiles.data_version/0`)."
  def data_version do
    case :persistent_term.get(@version_key, nil) do
      nil -> refresh_data_version()
      version -> version
    end
  end

  def refresh_data_version do
    version =
      case Repo.query!(
             "SELECT max(updated_at), count(*) FROM snapshots WHERE key LIKE 'market:%'"
           ).rows do
        [[nil, _]] -> "empty"
        [[updated_at, count]] -> "#{updated_at}-#{count}"
      end

    :persistent_term.put(@version_key, version)
    version
  end
end
