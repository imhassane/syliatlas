defmodule SyliAtlas.Workers.SearchConsoleWorker do
  @moduledoc """
  Each morning (cron, 07:00 UTC): the last days of Google Search Console.
  Google's figures arrive about two days late and keep changing for a few
  days, so the run reads again the five days ending two days ago. Without a
  key (`GOOGLE_SEARCH_CONSOLE_KEY`), nothing happens.
  """
  use Oban.Worker,
    queue: :seo,
    max_attempts: 3,
    unique: [period: 3600, states: [:available, :scheduled, :executing, :retryable]]

  require Logger
  alias SyliAtlas.SearchConsole

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    if SearchConsole.configured?() do
      back = Map.get(args, "days", 5)
      last = Date.add(Date.utc_today(), -2)
      days = for i <- (back - 1)..0//-1, do: Date.add(last, -i)

      case SearchConsole.import_days(days) do
        {:ok, n} ->
          Logger.info("search console: #{n} rows for #{hd(days)} → #{last}")
          :ok

        {:error, reason} ->
          Logger.error("search console import failed: #{inspect(reason)}")
          {:error, reason}
      end
    else
      Logger.warning("search console: no key or property set, nothing imported")
      {:cancel, :not_configured}
    end
  end
end
