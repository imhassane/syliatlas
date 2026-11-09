defmodule SyliAtlas.Workers.AfterPublishWorker do
  @moduledoc """
  Work that follows a publication: warm the query statistics so the admin
  can compare them with the 1.5 ms budget, and notify subscribers.
  """
  use Oban.Worker, queue: :computations, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"edition_id" => _id}}) do
    SyliAtlas.Profiles.Benchmark.run(200)
    :ok
  end
end
