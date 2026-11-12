defmodule SyliAtlas.Workers.FxBackfillWorker do
  @moduledoc """
  Fetches the days missing from the primary source over the last `days`
  (400 by default: the year-on-year comparison needs a year), one request
  per day, then publishes again. The source keeps its history by date,
  with no quota.
  """
  use Oban.Worker,
    queue: :market,
    max_attempts: 3,
    unique: [period: 86_400, states: [:available, :scheduled, :executing, :retryable]]

  require Logger
  alias SyliAtlas.Fx

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    days = Map.get(args, "days", 400)
    missing = Fx.missing_days(days)

    {ok, failed} =
      Enum.reduce(missing, {0, 0}, fn day, {ok, failed} ->
        case Fx.import(Fx.primary(), day) do
          {:ok, _day, _n} ->
            {ok + 1, failed}

          {:error, reason} ->
            Logger.warning("fx backfill #{day}: #{inspect(reason)}")
            {ok, failed + 1}
        end
      end)

    Logger.info("fx backfill: #{ok} days stored, #{failed} failed, #{length(missing)} asked")
    Fx.publish!()
    :ok
  end

  def enqueue(days \\ 400), do: Oban.insert(new(%{"days" => days}))
end
