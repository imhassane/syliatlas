defmodule SyliAtlas.Workers.AlertEventWorker do
  @moduledoc """
  An event alerts may react to: a published rating decision, a new IMF
  edition, a market session published, a budget law approved. Writes the deliveries and enqueues their emails
  (`SyliAtlas.Accounts.AlertEvents`). Safe to run twice.
  """
  use Oban.Worker,
    queue: :alerts,
    max_attempts: 5,
    # Only queued duplicates merge: a later market publish of the same
    # evening must run again (deliveries are unique per session anyway).
    unique: [
      keys: [:type, :rating_id, :edition_id, :law_id],
      period: 3600,
      states: [:available, :scheduled, :retryable]
    ]

  alias SyliAtlas.Accounts.AlertEvents

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "rating", "rating_id" => id}}) do
    AlertEvents.on_rating(id)
    :ok
  end

  def perform(%Oban.Job{args: %{"type" => "budget_law", "law_id" => id}}) do
    AlertEvents.on_budget_law(id)
    :ok
  end

  def perform(%Oban.Job{args: %{"type" => "market"}}) do
    AlertEvents.on_market()
    :ok
  end

  def perform(%Oban.Job{args: %{"type" => "edition", "edition_id" => id} = args}) do
    opts = if today = args["today"], do: [today: Date.from_iso8601!(today)], else: []
    AlertEvents.on_edition(id, opts)
    :ok
  end
end
