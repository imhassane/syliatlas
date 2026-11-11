defmodule SyliAtlas.Workers.MarketImportWorker do
  @moduledoc """
  Fetches a source and keeps each response raw, then enqueues one
  processing job per payload. Two passes on weekdays, set on Mansa's own
  refresh times (most exchanges at 16:30 UTC, the VFEX at 20:00):

    * 16:45 UTC, full: every dataset, about 28 calls;
    * 20:15 UTC, catch-up (`"mode" => "catchup"`): only the securities of
      the exchanges whose last session is still before today, at most
      8 of them, so 1 to 8 calls.

  About 30 calls a day for a free quota of 100, checked before every call.
  """
  use Oban.Worker, queue: :market, max_attempts: 3, unique: [period: 3600]

  import Ecto.Query
  require Logger
  alias SyliAtlas.Market.{Ingestion, Reference, Source}
  alias SyliAtlas.Workers.MarketProcessWorker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    source = Map.get(args, "source", "mansa")
    mod = Source.module(source)

    if Code.ensure_loaded?(mod) and function_exported?(mod, :configured?, 0) and
         not mod.configured?() do
      Logger.error("market import #{source}: no API key configured, nothing fetched")
      {:cancel, "#{source}: no API key configured"}
    else
      run(source, mod, Map.get(args, "mode", "full"))
    end
  end

  @catchup_max 8

  def run(source, mod, mode \\ "full") do
    exchanges = Reference.mappings(source, "exchange")
    by_id = Map.new(Reference.list_exchanges(), &{&1.id, &1.code})

    stocks =
      for {ext, id} <- Enum.sort_by(exchanges, &elem(&1, 0)), do: {"stocks", ext, by_id[id]}

    plan =
      case mode do
        "catchup" ->
          behind = behind_exchange_ids()

          stocks
          |> Enum.filter(fn {_, ext, _} -> exchanges[ext] in behind end)
          |> Enum.take(@catchup_max)

        _full ->
          [{"exchanges", nil, nil}, {"indices", nil, nil}] ++
            stocks ++ [{"etfs", nil, "ngx"}, {"forex", nil, nil}]
      end

    if plan == [] do
      :ok
    else
      fetch_plan(source, mod, plan)
    end
  end

  # Exchanges whose last consolidated session is before today. One that
  # never had any is left to the full import.
  defp behind_exchange_ids do
    today = Date.utc_today()

    latest =
      SyliAtlas.Repo.all(
        from p in SyliAtlas.Market.EodPrice,
          join: s in SyliAtlas.Market.Security,
          on: s.id == p.security_id,
          group_by: s.exchange_id,
          select: {s.exchange_id, type(max(p.trade_date), :date)}
      )
      |> Map.new()

    for e <- Reference.list_exchanges(),
        latest[e.id] != nil and Date.compare(latest[e.id], today) == :lt,
        do: e.id
  end

  defp fetch_plan(source, mod, plan) do
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
