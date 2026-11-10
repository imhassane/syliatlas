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

    results =
      Enum.map(plan, fn {dataset, ext, code} ->
        case mod.fetch(dataset, ext, []) do
          {:ok, responses} ->
            ids =
              for r <- responses do
                payload = Ingestion.store!(source, dataset, code, r)
                %{payload_id: payload.id} |> MarketProcessWorker.new() |> Oban.insert!()
                payload.id
              end

            {:ok, ids}

          {:error, reason} ->
            Logger.warning("market fetch #{source}/#{dataset} #{ext}: #{inspect(reason)}")
            {:error, reason}
        end
      end)

    SyliAtlas.Workers.MarketPublishWorker.new(%{}, schedule_in: 60) |> Oban.insert!()

    case Enum.count(results, &match?({:error, _}, &1)) do
      0 -> :ok
      n when n == length(results) -> {:error, "every fetch failed"}
      n -> {:ok, "#{n} fetches failed"}
    end
  end
end
