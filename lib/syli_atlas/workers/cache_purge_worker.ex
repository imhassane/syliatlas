defmodule SyliAtlas.Workers.CachePurgeWorker do
  @moduledoc """
  Drops the API answers from Cloudflare's cache after a publication
  (`SyliAtlas.Cdn.purge_api/0`). Retried a few times if Cloudflare does not
  answer; two publications close together make a single purge.
  """
  use Oban.Worker, queue: :computations, max_attempts: 5, unique: [period: 60]

  @impl Oban.Worker
  def perform(_job) do
    case SyliAtlas.Cdn.purge_api() do
      :ok -> :ok
      :skipped -> {:cancel, "Cloudflare is not configured"}
      {:error, reason} -> {:error, reason}
    end
  end
end
