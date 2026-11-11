defmodule SyliAtlas.Workers.AlertEmailWorker do
  @moduledoc """
  Sends one alert email. Retried alone with Oban's growing backoff when
  the mail service fails; never sent twice (`sent_at`).
  """
  use Oban.Worker,
    queue: :alerts,
    max_attempts: 8,
    unique: [
      keys: [:delivery_id],
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable, :completed]
    ]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"delivery_id" => id}}),
    do: SyliAtlas.Accounts.AlertEvents.send_delivery(id)
end
