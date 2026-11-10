defmodule SyliAtlas.Workers.RatingsWatchWorker do
  @moduledoc """
  Runs the ratings news watch every morning, and on demand from the admin.
  Its proposals wait in /admin/notations; nothing is published here.
  """
  use Oban.Worker, queue: :moderation, max_attempts: 3, unique: [period: 600]

  @impl Oban.Worker
  def perform(_job) do
    result = SyliAtlas.Ratings.Watch.run()
    {:ok, result}
  end
end
