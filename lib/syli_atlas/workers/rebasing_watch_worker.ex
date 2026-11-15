defmodule SyliAtlas.Workers.RebasingWatchWorker do
  @moduledoc """
  Runs the rebasing news watch every morning, and on demand from the admin.
  Its proposals wait in /admin/chiffres-nationaux; nothing is published here.
  """
  use Oban.Worker, queue: :moderation, max_attempts: 3, unique: [period: 600]

  @impl Oban.Worker
  def perform(_job), do: {:ok, SyliAtlas.National.Watch.run()}
end
