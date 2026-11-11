defmodule SyliAtlas.Workers.DigestWorker do
  @moduledoc """
  Each morning (cron, 06:40 UTC): enqueues the digest of every member whose
  digest falls today (Mondays; the 1st for monthly ones), one job each.
  """
  use Oban.Worker, queue: :alerts, max_attempts: 3, unique: [period: 3600]

  alias SyliAtlas.Accounts.Digests
  alias SyliAtlas.Workers.DigestEmailWorker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    today = if d = args["today"], do: Date.from_iso8601!(d), else: Date.utc_today()

    today
    |> Digests.due_user_ids()
    |> Enum.map(&DigestEmailWorker.new(%{"user_id" => &1, "date" => Date.to_iso8601(today)}))
    |> Oban.insert_all()

    :ok
  end
end
