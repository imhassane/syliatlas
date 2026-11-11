defmodule SyliAtlas.Workers.AlertEventWorker do
  @moduledoc """
  An event alerts may react to: a published rating decision, a new IMF
  edition. Writes the deliveries and enqueues their emails
  (`SyliAtlas.Accounts.AlertEvents`). Safe to run twice.
  """
  use Oban.Worker,
    queue: :alerts,
    max_attempts: 5,
    unique: [keys: [:type, :rating_id, :edition_id], period: 3600]

  alias SyliAtlas.Accounts.AlertEvents

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "rating", "rating_id" => id}}) do
    AlertEvents.on_rating(id)
    :ok
  end

  def perform(%Oban.Job{args: %{"type" => "edition", "edition_id" => id} = args}) do
    opts = if today = args["today"], do: [today: Date.from_iso8601!(today)], else: []
    AlertEvents.on_edition(id, opts)
    :ok
  end
end
