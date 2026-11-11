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
    # Market alerts read the documents just rebuilt; one event per window,
    # and each delivery is unique per session, so repeats send nothing.
    SyliAtlas.Accounts.AlertEvents.market_published()
    SyliAtlas.Workers.OgWarmWorker.enqueue()
    :ok
  end
end
