defmodule SyliAtlas.Workers.MarketImportWorker do
  @moduledoc """
  Runs after the last African close (17:30 UTC, Monday to Friday). Fetches
  every dataset of a source and keeps each response raw, then enqueues one
  processing job per payload. About 28 calls a day for Mansa: well under
  its free quota, checked before every call.
  """
  use Oban.Worker, queue: :market, max_attempts: 3, unique: [period: 3600]

  require Logger
  alias SyliAtlas.Market.{Ingestion, Reference, Source}
  alias SyliAtlas.Workers.MarketProcessWorker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    source = Map.get(args, "source", "mansa")
    mod = Source.module(source)

    if function_exported?(mod, :configured?, 0) and not mod.configured?() do
      Logger.error("market import #{source}: no API key configured, nothing fetched")
      {:cancel, "#{source}: no API key configured"}
    else
      run(source, mod)
    end
  end

  def run(source, mod) do
    exchanges = Reference.mappings(source, "exchange")
    by_id = Map.new(Reference.list_exchanges(), &{&1.id, &1.code})

    plan =
      [{"exchanges", nil, nil}, {"indices", nil, nil}] ++
        for({ext, id} <- Enum.sort_by(exchanges, &elem(&1, 0)), do: {"stocks", ext, by_id[id]}) ++
        [{"etfs", nil, "ngx"}, {"forex", nil, nil}]

    {results, stop} =
      Enum.reduce_while(plan, {[], nil}, fn {dataset, ext, code}, {acc, nil} ->
        case mod.fetch(dataset, ext, []) do
          {:ok, responses} ->
            ids =
              for r <- responses do
                payload = Ingestion.store!(source, dataset, code, r)
                %{payload_id: payload.id} |> MarketProcessWorker.new() |> Oban.insert!()
                payload.id
              end

            {:cont, {[{:ok, ids} | acc], nil}}

          # Daily quota used up (the source said so, or our own cap): stop
          # here, keep what came, try again once the quota is back.
          {:error, {:daily_limit, reset_at}} ->
            Ingestion.exhaust!(source)
            {:halt, {acc, reset_at}}

          {:error, :quota_exhausted} ->
            {:halt, {acc, next_midnight()}}

          {:error, reason} ->
            Logger.warning("market fetch #{source}/#{dataset} #{ext}: #{inspect(reason)}")
            {:cont, {[{:error, reason} | acc], nil}}
        end
      end)

    if results != [] do
      SyliAtlas.Workers.MarketPublishWorker.new(%{}, schedule_in: 60) |> Oban.insert!()
    end

    cond do
      stop != nil ->
        retry_at = DateTime.add(stop, 10 * 60)

        Logger.error(
          "market import #{source}: daily quota used up after #{length(results)} of " <>
            "#{length(plan)} fetches, next try at #{retry_at}"
        )

        %{source: source} |> new(scheduled_at: retry_at) |> Oban.insert!()
        {:ok, "quota used up, retry at #{retry_at}"}

      Enum.all?(results, &match?({:error, _}, &1)) ->
        {:error, "every fetch failed"}

      true ->
        case Enum.count(results, &match?({:error, _}, &1)) do
          0 -> :ok
          n -> {:ok, "#{n} fetches failed"}
        end
    end
  end

  defp next_midnight do
    Date.utc_today() |> Date.add(1) |> DateTime.new!(~T[00:00:00]) |> DateTime.truncate(:second)
  end
end
