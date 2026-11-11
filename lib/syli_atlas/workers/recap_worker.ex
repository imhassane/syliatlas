defmodule SyliAtlas.Workers.RecapWorker do
  @moduledoc """
  Each morning (cron, 06:45 UTC): deletes the subscriptions never
  confirmed, then enqueues the country recap of every confirmed address
  due today (Mondays; the 1st for monthly ones), one job each.
  """
  use Oban.Worker, queue: :alerts, max_attempts: 3, unique: [period: 3600]

  alias SyliAtlas.Recaps
  alias SyliAtlas.Workers.RecapEmailWorker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    today = if d = args["today"], do: Date.from_iso8601!(d), else: Date.utc_today()

    Recaps.purge_unconfirmed()

    today
    |> Recaps.due_ids()
    |> Enum.map(
      &RecapEmailWorker.new(%{"subscription_id" => &1, "date" => Date.to_iso8601(today)})
    )
    |> Oban.insert_all()

    :ok
  end
end
