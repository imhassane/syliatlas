defmodule SyliAtlas.Workers.SocialSyncWorker do
  @moduledoc """
  Every half hour: what Buffer did with the posts (`SyliAtlas.Social.sync/0`).
  Asks nothing when no post waits in its queue or went out in the last
  days, and nothing outside production (simulated).
  """
  use Oban.Worker, queue: :social, max_attempts: 1, unique: [period: 600]

  @impl Oban.Worker
  def perform(_job) do
    if SyliAtlas.Social.sync_needed?() do
      case SyliAtlas.Social.sync() do
        {:ok, _} -> :ok
        {:error, message} -> {:error, message}
      end
    else
      :ok
    end
  end
end
