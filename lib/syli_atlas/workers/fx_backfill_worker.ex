defmodule SyliAtlas.Workers.FxBackfillWorker do
  @moduledoc """
  Fetches the days missing from the primary source over the last `days`
  (by default every day since the source's first dated release, about two
  and a half years: the year-on-year comparison needs one, the simulator
  converts the start of a placement with the rate of its day), one request
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
    days = Map.get(args, "days") || default_days()
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

  def enqueue(days \\ nil), do: Oban.insert(new(%{"days" => days || default_days()}))

  defp default_days,
    do: Date.diff(Date.utc_today(), SyliAtlas.Fx.Sources.ExchangeApi.first_day())
end
