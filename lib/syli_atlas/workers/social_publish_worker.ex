defmodule SyliAtlas.Workers.SocialPublishWorker do
  @moduledoc """
  Sends an approved post to X and/or LinkedIn through the publisher
  (`SyliAtlas.Social.publish/1`): Buffer's queue in production, simulated
  elsewhere. A failed network is retried, a sent one never twice.
  """
  use Oban.Worker,
    queue: :social,
    max_attempts: 5,
    unique: [keys: [:post_id], period: 60, states: [:available, :scheduled, :retryable]]

  alias SyliAtlas.Social

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"post_id" => id}}) do
    case SyliAtlas.Repo.get(SyliAtlas.Social.Post, id) do
      nil -> :ok
      post -> Social.publish(post)
    end
  end
end
