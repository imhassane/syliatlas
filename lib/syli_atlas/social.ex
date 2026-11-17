defmodule SyliAtlas.Social do
  @moduledoc """
  Posts for X and LinkedIn (canvas « Syli Atlas — publication sur X et
  LinkedIn »):

    1. an event of the site prepares a draft (`SyliAtlas.Social.Drafts`);
    2. a person edits it, then approves it for both networks or one, or
       rejects it, in /admin/reseaux;
    3. `SyliAtlas.Workers.SocialPublishWorker` hands it to the publisher
       (`SyliAtlas.Social.Publisher`): Buffer's queue in production,
       simulated elsewhere. Buffer then posts at the next slot of its
       schedule.

  Nothing is ever posted without a person's approval.
  """
  import Ecto.Query
  require Logger

  alias SyliAtlas.Repo
  alias SyliAtlas.Social.{Post, Publisher}
  alias SyliAtlas.Workers.SocialPublishWorker

  @doc "Stores a draft unless the event already has one (same key): returns the post or :exists."
  def create_draft(attrs) do
    %Post{}
    |> Post.draft_changeset(attrs)
    |> Repo.insert(on_conflict: :nothing, conflict_target: :key)
    |> case do
      {:ok, %Post{id: nil}} ->
        :exists

      {:ok, post} ->
        {:ok, post}

      {:error, changeset} ->
        Logger.warning("social: draft refused: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  def get!(id), do: Repo.get!(Post, id)

  @doc "Drafts waiting, most important first."
  def drafts do
    Repo.all(
      from p in Post,
        where: p.status == "draft",
        order_by: [desc: p.priority, desc: p.inserted_at, desc: p.id]
    )
  end

  @doc "Posts already decided, newest first."
  def history(limit \\ 50) do
    Repo.all(
      from p in Post,
        where: p.status != "draft",
        order_by: [desc: p.updated_at, desc: p.id],
        limit: ^limit
    )
  end

  def count_drafts, do: Repo.aggregate(from(p in Post, where: p.status == "draft"), :count)

  @doc "Counters of the page."
  def stats do
    since = DateTime.add(DateTime.utc_now(), -7, :day)

    sent =
      Repo.aggregate(
        from(p in Post, where: p.status == "done" and p.sent_at > ^since),
        :count
      )

    failed =
      Repo.aggregate(
        from(p in Post,
          where: p.x_state == "failed" or p.linkedin_state == "failed",
          where: p.updated_at > ^since
        ),
        :count
      )

    %{drafts: count_drafts(), sent: sent, failed: failed, simulated: Publisher.simulated?()}
  end

  @doc "The accounts the publisher can post to (Buffer's connected channels)."
  def channels do
    Publisher.adapter().channels()
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc "A person rewrites the texts."
  def update_texts(%Post{status: "draft"} = post, attrs),
    do: post |> Post.edit_changeset(attrs) |> Repo.update()

  def update_texts(%Post{} = post, _attrs), do: {:error, post}

  @doc """
  A person approves a draft for `networks` (["x", "linkedin"] or one of
  them), with the texts as they stand: the post is sent by a job.
  """
  def approve(%Post{status: "draft"} = post, networks, attrs, who) do
    networks = Enum.filter(networks, &(&1 in Post.networks()))

    if networks == [] do
      {:error, :no_network}
    else
      Repo.transaction(fn ->
        changes =
          %{status: "approved", reviewed_by: who, reviewed_at: now()}
          |> Map.put(:x_state, if("x" in networks, do: "pending"))
          |> Map.put(:linkedin_state, if("linkedin" in networks, do: "pending"))

        post =
          post
          |> Post.edit_changeset(attrs)
          |> Ecto.Changeset.change(changes)
          |> Repo.update()
          |> case do
            {:ok, post} -> post
            {:error, changeset} -> Repo.rollback(changeset)
          end

        %{"post_id" => post.id} |> SocialPublishWorker.new() |> Oban.insert!()
        post
      end)
    end
  end

  def approve(%Post{}, _networks, _attrs, _who), do: {:error, :not_draft}

  @doc """
  Sends a post again on one network (« Renvoyer »): after a failure, or when
  the post was deleted in Buffer. Its other network is left as it is.
  """
  def resend(%Post{status: status} = post, network)
      when status in ["approved", "done"] and network in ["x", "linkedin"] do
    state = String.to_existing_atom(network <> "_state")

    if Map.get(post, state) in ["queued", "simulated", "failed"] do
      Repo.transaction(fn ->
        post =
          post
          |> Ecto.Changeset.change(%{
            :status => "approved",
            state => "pending",
            String.to_existing_atom(network <> "_ref") => nil,
            String.to_existing_atom(network <> "_error") => nil
          })
          |> Repo.update!()

        %{"post_id" => post.id} |> SocialPublishWorker.new() |> Oban.insert!()
        post
      end)
    else
      {:error, :nothing_to_resend}
    end
  end

  def resend(%Post{}, _network), do: {:error, :nothing_to_resend}

  def reject(%Post{status: "draft"} = post, who) do
    post
    |> Ecto.Changeset.change(status: "rejected", reviewed_by: who, reviewed_at: now())
    |> Repo.update()
  end

  def reject(%Post{}, _who), do: {:error, :not_draft}

  @doc """
  Sends each pending network of an approved post (the job). A network
  already queued is never sent again: a retried job only redoes the
  failures. Returns :ok when every network answered, {:error, reason} to
  let Oban retry.
  """
  def publish(%Post{status: "approved"} = post) do
    adapter = Publisher.adapter()
    simulated = Publisher.simulated?()

    post =
      Enum.reduce(Post.networks(), post, fn network, post ->
        state_key = String.to_existing_atom(network <> "_state")

        if Map.get(post, state_key) in ["pending", "failed"] do
          send_one(post, adapter, String.to_existing_atom(network), simulated)
        else
          post
        end
      end)

    if Enum.any?([post.x_state, post.linkedin_state], &(&1 == "failed")) do
      {:error, Enum.join(Enum.reject([post.x_error, post.linkedin_error], &is_nil/1), " ; ")}
    else
      post
      |> Ecto.Changeset.change(status: "done", sent_at: now())
      |> Repo.update!()

      :ok
    end
  end

  def publish(%Post{}), do: :ok

  defp send_one(post, adapter, network, simulated) do
    payload =
      case network do
        :x ->
          %{text: Post.x_body(post), image_url: post.image_url_x || post.image_url}

        :linkedin ->
          %{text: Post.linkedin_body(post), image_url: post.image_url}
      end

    {state, ref, error} =
      case adapter.publish(network, payload) do
        {:ok, ref} -> {if(simulated, do: "simulated", else: "queued"), ref, nil}
        {:error, message} -> {"failed", nil, String.slice(to_string(message), 0, 250)}
      end

    post
    |> Ecto.Changeset.change(%{
      String.to_existing_atom("#{network}_state") => state,
      String.to_existing_atom("#{network}_ref") => ref,
      String.to_existing_atom("#{network}_error") => error
    })
    |> Repo.update!()
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
