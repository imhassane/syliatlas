defmodule SyliAtlas.Workers.FxImportWorker do
  @moduledoc """
  Each night (cron, after the sources' daily update): today's rates from
  the primary source, the check source, then the document of the pages.
  On the first run, or after a gap, it asks `FxBackfillWorker` for the
  missing days of the last year.
  """
  use Oban.Worker,
    queue: :market,
    max_attempts: 5,
    unique: [period: 3600, states: [:available, :scheduled, :executing, :retryable]]

  require Logger
  alias SyliAtlas.Fx

  @impl Oban.Worker
  def perform(_job) do
    primary = Fx.import(Fx.primary(), :latest)

    case Fx.import(Fx.shadow(), :latest) do
      {:ok, _day, _n} -> :ok
      {:error, reason} -> Logger.warning("fx check source failed: #{inspect(reason)}")
    end

    case primary do
      {:ok, day, n} ->
        Logger.info("fx: #{n} rates for #{day}")
        Fx.publish!()

        if Fx.missing_days(30) != [] or history_short?(),
          do: SyliAtlas.Workers.FxBackfillWorker.enqueue()

        :ok

      {:error, reason} ->
        Logger.error("fx primary source failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # The stored history does not reach back to the source's first day (the
  # simulator converts the start of a placement with the rate of its day).
  defp history_short? do
    case Fx.first_stored_day() do
      nil -> true
      first -> Date.diff(first, SyliAtlas.Fx.Sources.ExchangeApi.first_day()) > 7
    end
  end

  @doc "Runs the import now unless the rates are already there (application start)."
  def enqueue_if_missing do
    if Fx.latest() == nil, do: Oban.insert(new(%{})), else: :ok
  end
end
