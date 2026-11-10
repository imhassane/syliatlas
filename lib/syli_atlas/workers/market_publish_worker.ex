defmodule SyliAtlas.Workers.MarketPublishWorker do
  @moduledoc """
  Rebuilds the documents of the market pages. Many payloads end within a
  few seconds of each other: the uniqueness window makes them share one
  rebuild.
  """
  use Oban.Worker,
    queue: :market,
    max_attempts: 3,
    unique: [period: 60, states: [:available, :scheduled, :retryable]]

  @impl Oban.Worker
  def perform(_job) do
    SyliAtlas.Market.Snapshots.rebuild!()
    :ok
  end
end
