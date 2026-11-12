defmodule SyliAtlas.Workers.IndexHistoryWorker do
  @moduledoc """
  Brings the past closes of the main indices once (Mansa's
  `/indices/{code}/history`, one call per index, within the daily quota),
  for the simulator. An index that already has more than three years of
  closes is skipped, so running it again costs nothing. Each response is
  kept raw and processed like any market payload; history never replaces a
  session already published.
  """
  use Oban.Worker,
    queue: :market,
    max_attempts: 3,
    unique: [period: 86_400, states: [:available, :scheduled, :executing, :retryable]]

  import Ecto.Query
  require Logger
  alias SyliAtlas.Market.{IndexValue, Ingestion, Reference}
  alias SyliAtlas.Market.Sources.Mansa
  alias SyliAtlas.Workers.{MarketProcessWorker, MarketPublishWorker}

  @years 3

  @impl Oban.Worker
  def perform(_job) do
    if Mansa.configured?() do
      run()
    else
      {:cancel, "mansa: no API key configured"}
    end
  end

  defp short_history?(nil, _cutoff), do: true
  defp short_history?(first, cutoff), do: Date.compare(first, cutoff) == :gt

  def run do
    exchanges = Reference.mappings("mansa", "exchange")
    by_id = Map.new(Reference.list_exchanges(), &{&1.id, &1})
    cutoff = Date.add(Date.utc_today(), -365 * @years)

    todo =
      for {ext, _index} <- Mansa.history_codes(),
          id = exchanges[ext],
          id != nil,
          short_history?(first_close(id), cutoff),
          do: {ext, by_id[id].code}

    results =
      for {ext, code} <- todo do
        case Mansa.fetch("index_history", ext, []) do
          {:ok, responses} ->
            for r <- responses do
              payload = Ingestion.store!("mansa", "index_history", code, r)
              %{payload_id: payload.id} |> MarketProcessWorker.new() |> Oban.insert!()
            end

            :ok

          {:error, reason} ->
            Logger.warning("index history #{code}: #{inspect(reason)}")
            {:error, reason}
        end
      end

    if Enum.any?(results, &(&1 == :ok)),
      do: MarketPublishWorker.new(%{}, schedule_in: 120) |> Oban.insert!()

    Logger.info(
      "index history: #{length(todo)} asked, #{Enum.count(results, &(&1 == :ok))} fetched"
    )

    :ok
  end

  defp first_close(exchange_id) do
    SyliAtlas.Repo.one(
      from v in IndexValue, where: v.exchange_id == ^exchange_id, select: min(v.trade_date)
    )
    |> case do
      nil -> nil
      %Date{} = d -> d
      text when is_binary(text) -> Date.from_iso8601!(text)
    end
  end

  def enqueue, do: Oban.insert(new(%{}))
end
