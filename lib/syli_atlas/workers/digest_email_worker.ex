defmodule SyliAtlas.Workers.DigestEmailWorker do
  @moduledoc "Builds and sends one member's digest; retried alone if the mail service fails."
  use Oban.Worker,
    queue: :alerts,
    max_attempts: 5,
    unique: [
      keys: [:user_id, :date],
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable, :completed]
    ]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => id, "date" => date}}),
    do: SyliAtlas.Accounts.Digests.send(id, Date.from_iso8601!(date))
end
