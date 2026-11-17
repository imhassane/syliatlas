defmodule SyliAtlas.Workers.SocialPublishWorker do
  @moduledoc """
  Sends an approved post to X and/or LinkedIn through the publisher
  (`SyliAtlas.Social.publish/2`): Buffer in production, simulated elsewhere.
  `"mode" => "now"` publishes at once, else Buffer's next free slot. A
  failed network is retried, a sent one never twice.
  """
  use Oban.Worker,
    queue: :social,
    max_attempts: 5,
    unique: [keys: [:post_id], period: 60, states: [:available, :scheduled, :retryable]]

  alias SyliAtlas.Social

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"post_id" => id} = args}) do
    mode = if args["mode"] == "now", do: :now, else: :queue

    case SyliAtlas.Repo.get(SyliAtlas.Social.Post, id) do
      nil -> :ok
      post -> Social.publish(post, mode)
    end
  end
end
