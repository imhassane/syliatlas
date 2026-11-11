defmodule SyliAtlas.Workers.RecapEmailWorker do
  @moduledoc "Builds and sends one country recap; retried alone if the mail service fails."
  use Oban.Worker,
    queue: :alerts,
    max_attempts: 5,
    unique: [
      keys: [:subscription_id, :date],
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable, :completed]
    ]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"subscription_id" => id, "date" => date}}),
    do: SyliAtlas.Recaps.send(id, Date.from_iso8601!(date))
end
