defmodule SyliAtlas.Social do
  @moduledoc """
  Posts for X and LinkedIn (canvas « Syli Atlas — publication sur X et
  LinkedIn », artboard C):

    1. a draft comes from an event of the site (`SyliAtlas.Social.Drafts`)
       or from any public page (`SyliAtlas.Social.Pages`: « Partager sur
       les réseaux », in the admin bar of the page or in /admin/reseaux);
    2. a person edits it, then schedules it (Buffer's next free slot),
       publishes it now, puts it in the queue without a date (« En file »,
       kept here) or rejects it, for both networks or one;
    3. `SyliAtlas.Workers.SocialPublishWorker` hands it to the publisher
       (`SyliAtlas.Social.Publisher`): Buffer in production, simulated
       elsewhere;
    4. `sync/0` (every half hour, and « Actualiser ») reads back what Buffer
       did: due time, sent, error, figures.

  Nothing is ever posted without a person's approval.
  """
  import Ecto.Query
  require Logger

  alias SyliAtlas.Repo
  alias SyliAtlas.Social.{Clock, Post, Publisher}
  alias SyliAtlas.Workers.SocialPublishWorker

  # Buffer's free plan: 10 posts scheduled per channel at a time.
  @quota 10
  def quota_limit, do: @quota

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

  @doc "Approved posts without a date (« En file »), oldest first."
  def ready do
    Repo.all(from p in Post, where: p.status == "ready", order_by: [asc: p.updated_at, asc: p.id])
  end

  @doc "Posts already decided, newest first."
  def history(limit \\ 50) do
    Repo.all(
      from p in Post,
        where: p.status not in ["draft", "ready"],
        order_by: [desc: p.updated_at, desc: p.id],
        limit: ^limit
    )
  end

  @doc """
  The columns of /admin/reseaux: `drafts`, `ready`, `scheduled` (in Buffer's
  queue, by due time), `published` (newest first), `failed`.
  """
  def board do
    sent = history(200)

    %{
      drafts: drafts(),
      ready: ready(),
      scheduled:
        sent
        |> Enum.filter(&any_state?(&1, ["queued", "pending"]))
        |> Enum.sort_by(&(first_due(&1) || ~U[2999-01-01 00:00:00Z]), DateTime),
      published:
        sent
        |> Enum.filter(&any_state?(&1, ["sent", "simulated"]))
        |> Enum.sort_by(&(last_sent(&1) || ~U[1970-01-01 00:00:00Z]), {:desc, DateTime})
        |> Enum.take(12),
      failed: Enum.filter(sent, &any_state?(&1, ["failed"]))
    }
  end

  defp any_state?(p, states), do: p.x_state in states or p.linkedin_state in states

  @doc "The earliest slot a post is due at, on either network."
  def first_due(%Post{} = p) do
    [p.x_state == "queued" && p.x_due_at, p.linkedin_state == "queued" && p.linkedin_due_at]
    |> Enum.filter(& &1)
    |> Enum.min(DateTime, fn -> nil end)
  end

  @doc "When a post last went out, on either network."
  def last_sent(%Post{} = p) do
    [p.x_sent_at, p.linkedin_sent_at, p.sent_at]
    |> Enum.filter(& &1)
    |> Enum.max(DateTime, fn -> nil end)
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
        from(p in Post, where: p.x_state == "failed" or p.linkedin_state == "failed"),
        :count
      )

    %{
      drafts: count_drafts(),
      ready: Repo.aggregate(from(p in Post, where: p.status == "ready"), :count),
      sent: sent,
      failed: failed,
      simulated: Publisher.simulated?()
    }
  end

  @doc "Posts in Buffer's queue per network, against the free plan's #{@quota}."
  def quota do
    %{
      x: Repo.aggregate(from(p in Post, where: p.x_state in ["queued", "pending"]), :count),
      linkedin:
        Repo.aggregate(from(p in Post, where: p.linkedin_state in ["queued", "pending"]), :count),
      limit: @quota
    }
  end

  @doc "Networks whose queue is full: scheduling waits there."
  def full_networks do
    q = quota()
    for n <- Post.networks(), Map.fetch!(q, String.to_existing_atom(n)) >= @quota, do: n
  end

  @doc "The accounts the publisher can post to (Buffer's connected channels)."
  def channels do
    Publisher.adapter().channels()
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc "A person rewrites the texts."
  def update_texts(%Post{status: status} = post, attrs) when status in ["draft", "ready"],
    do: post |> Post.edit_changeset(attrs) |> Repo.update()

  def update_texts(%Post{} = post, _attrs), do: {:error, post}

  @doc """
  A post for a page of the site (`SyliAtlas.Social.Pages.draft/2`), with
  the texts as the person left them, then what they chose: `"draft"` (to
  approve later), `"queue"` (« Ajouter à la file »), `"schedule"`, `"now"`.
  """
  def share_page(attrs, texts, networks, action, who) do
    networks = Enum.filter(networks, &(&1 in Post.networks()))

    if networks == [] do
      {:error, :no_network}
    else
      case create_draft(Map.merge(attrs, texts)) do
        {:ok, post} ->
          post = mark_waiting(post, networks)

          case action do
            "queue" -> put_ready(post, networks, %{}, who)
            "schedule" -> approve(post, networks, %{}, who)
            "now" -> approve(post, networks, %{}, who, :now)
            _ -> {:ok, post}
          end

        :exists ->
          {:error, :exists}

        error ->
          error
      end
    end
  end

  defp mark_waiting(post, networks) do
    post
    |> Ecto.Changeset.change(waiting(networks))
    |> Repo.update!()
  end

  defp waiting(networks),
    do: %{
      x_state: if("x" in networks, do: "waiting"),
      linkedin_state: if("linkedin" in networks, do: "waiting")
    }

  @doc """
  « Ajouter à la file »: approved without a date, kept here (nothing goes
  to Buffer, nothing counts against its quota) until a person schedules it.
  """
  def put_ready(%Post{status: status} = post, networks, attrs, who)
      when status in ["draft", "ready"] do
    networks = Enum.filter(networks, &(&1 in Post.networks()))

    if networks == [] do
      {:error, :no_network}
    else
      post
      |> Post.edit_changeset(attrs)
      |> Ecto.Changeset.change(
        Map.merge(waiting(networks), %{status: "ready", reviewed_by: who, reviewed_at: now()})
      )
      |> Repo.update()
    end
  end

  def put_ready(%Post{}, _networks, _attrs, _who), do: {:error, :not_draft}

  @doc """
  A person approves a draft or a queued post for `networks` (["x",
  "linkedin"] or one of them), with the texts as they stand: the post is
  sent by a job, to Buffer's next free slot (`:queue`) or at once (`:now`).
  """
  def approve(post, networks, attrs, who, mode \\ :queue)

  def approve(%Post{status: status} = post, networks, attrs, who, mode)
      when status in ["draft", "ready"] do
    networks = Enum.filter(networks, &(&1 in Post.networks()))

    if networks == [] do
      {:error, :no_network}
    else
      Repo.transaction(fn ->
        changes =
          %{status: "approved", reviewed_by: who, reviewed_at: now()}
          |> Map.merge(%{x_due_at: nil, linkedin_due_at: nil})
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

        enqueue(post, mode)
        post
      end)
    end
  end

  def approve(%Post{}, _networks, _attrs, _who, _mode), do: {:error, :not_draft}

  defp enqueue(post, mode) do
    args = %{"post_id" => post.id}
    args = if mode == :now, do: Map.put(args, "mode", "now"), else: args
    args |> SocialPublishWorker.new() |> Oban.insert!()
  end

  @doc """
  « Retirer »: takes a scheduled post out of Buffer's queue and puts it back
  in « En file », for the same networks. Only before anything went out.
  """
  def withdraw(%Post{status: status} = post, who) when status in ["approved", "done"] do
    queued = for n <- Post.networks(), state(post, n) == "queued", do: n

    cond do
      queued == [] or Enum.any?(Post.networks(), &(state(post, &1) in ["sent", "pending"])) ->
        {:error, :not_scheduled}

      true ->
        adapter = Publisher.adapter()

        failures =
          for n <- queued,
              ref = Map.get(post, ref_key(n)),
              is_binary(ref),
              not String.starts_with?(ref, "simulated-"),
              result = adapter.delete(ref),
              result != :ok,
              do: result

        case failures do
          [] ->
            post
            |> Ecto.Changeset.change(
              Map.merge(waiting(queued), %{
                status: "ready",
                x_ref: nil,
                linkedin_ref: nil,
                x_due_at: nil,
                linkedin_due_at: nil,
                x_error: nil,
                linkedin_error: nil,
                reviewed_by: who,
                reviewed_at: now()
              })
            )
            |> Repo.update()

          [{:error, message} | _] ->
            {:error, message}
        end
    end
  end

  def withdraw(%Post{}, _who), do: {:error, :not_scheduled}

  @doc "« Publier maintenant » for a scheduled post: out of the queue, then at once."
  def publish_now(%Post{status: "ready"} = post, who),
    do: approve(post, Post.chosen(post), %{}, who, :now)

  def publish_now(%Post{} = post, who) do
    with {:ok, post} <- withdraw(post, who) do
      approve(post, Post.chosen(post), %{}, who, :now)
    end
  end

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
            String.to_existing_atom(network <> "_error") => nil,
            String.to_existing_atom(network <> "_due_at") => nil
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

  def reject(%Post{status: status} = post, who) when status in ["draft", "ready"] do
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
  def publish(post, mode \\ :queue)

  def publish(%Post{status: "approved"} = post, mode) do
    adapter = Publisher.adapter()
    simulated = Publisher.simulated?()

    post =
      Enum.reduce(Post.networks(), post, fn network, post ->
        if state(post, network) in ["pending", "failed"] do
          send_one(post, adapter, String.to_existing_atom(network), simulated, mode)
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

  def publish(%Post{}, _mode), do: :ok

  defp send_one(post, adapter, network, simulated, mode) do
    payload =
      case network do
        :x ->
          %{text: Post.x_body(post), image_url: Post.x_image(post)}

        :linkedin ->
          %{text: Post.linkedin_body(post), image_url: post.image_url}
      end

    {state, ref, error} =
      case adapter.publish(network, payload, mode) do
        {:ok, ref} -> {if(simulated, do: "simulated", else: "queued"), ref, nil}
        {:error, message} -> {"failed", nil, String.slice(to_string(message), 0, 250)}
      end

    # Published at once: the slot is now (Buffer confirms at the next sync).
    sent_now = if mode == :now and state in ["queued", "simulated"], do: now()

    post
    |> Ecto.Changeset.change(%{
      String.to_existing_atom("#{network}_state") => state,
      String.to_existing_atom("#{network}_ref") => ref,
      String.to_existing_atom("#{network}_error") => error,
      String.to_existing_atom("#{network}_due_at") => sent_now,
      String.to_existing_atom("#{network}_sent_at") => if(state == "simulated", do: now())
    })
    |> Repo.update!()
  end

  # Buffer's side ------------------------------------------------------------

  @doc """
  Reads back from Buffer every post still in its queue or sent in the last
  #{7} days (their figures move): due time, sent, error, figures. A queued
  post Buffer no longer has was deleted there: it is marked failed, so
  « Renvoyer » can send it again.
  """
  def sync do
    if Publisher.simulated?() do
      {:ok, 0}
    else
      posts = to_sync()
      refs = for p <- posts, n <- Post.networks(), ref = real_ref(p, n), do: ref

      case Publisher.adapter().posts(refs) do
        {:ok, remote} ->
          count = Enum.count(posts, &apply_remote(&1, remote))
          :persistent_term.put({__MODULE__, :synced}, {DateTime.utc_now(), :ok})
          {:ok, count}

        {:error, message} = error ->
          Logger.warning("social: sync failed: #{message}")
          :persistent_term.put({__MODULE__, :synced}, {DateTime.utc_now(), {:error, message}})
          error
      end
    end
  end

  @doc "When Buffer was last read, and how it went."
  def last_sync, do: :persistent_term.get({__MODULE__, :synced}, nil)

  @doc "Whether anything is worth asking Buffer about."
  def sync_needed?, do: not Publisher.simulated?() and to_sync() != []

  defp to_sync do
    since = DateTime.add(DateTime.utc_now(), -7, :day)

    Repo.all(
      from p in Post,
        where: p.status in ["approved", "done"],
        where:
          p.x_state in ["queued", "pending"] or p.linkedin_state in ["queued", "pending"] or
            (p.x_state == "sent" and p.x_sent_at > ^since) or
            (p.linkedin_state == "sent" and p.linkedin_sent_at > ^since)
    )
  end

  defp real_ref(post, network) do
    ref = Map.get(post, ref_key(network))

    if is_binary(ref) and not String.starts_with?(ref, "simulated-") and
         state(post, network) in ["queued", "sent"],
       do: ref
  end

  defp apply_remote(post, remote) do
    changes =
      for n <- Post.networks(), ref = real_ref(post, n), reduce: %{} do
        acc ->
          case remote[ref] do
            nil ->
              if state(post, n) == "queued",
                do:
                  Map.merge(acc, %{
                    key(n, "state") => "failed",
                    key(n, "error") => "Introuvable dans Buffer : supprimé ?"
                  }),
                else: acc

            %{status: "sent"} = r ->
              Map.merge(acc, %{
                key(n, "state") => "sent",
                key(n, "sent_at") => r.sent_at || r.due_at,
                key(n, "due_at") => r.due_at,
                key(n, "metrics") => r.metrics,
                key(n, "error") => nil
              })

            %{status: "error"} = r ->
              Map.merge(acc, %{
                key(n, "state") => "failed",
                key(n, "error") =>
                  String.slice(r.error || "Erreur de publication (Buffer)", 0, 250)
              })

            r ->
              Map.merge(acc, %{key(n, "state") => "queued", key(n, "due_at") => r.due_at})
          end
      end

    post
    |> Ecto.Changeset.change(Map.put(changes, :synced_at, now()))
    |> Repo.update!()

    changes != %{}
  end

  defp key(network, field), do: String.to_existing_atom("#{network}_#{field}")
  defp ref_key(network), do: key(network, "ref")
  defp state(post, network), do: Map.get(post, key(network, "state"))

  @schedule_ttl 3600

  @doc "Buffer's posting schedule (X's account, kept an hour), else the known one."
  def schedule do
    cache = {__MODULE__, :schedule}
    now = System.system_time(:second)

    case :persistent_term.get(cache, nil) do
      {s, at} when now - at < @schedule_ttl and not is_nil(s) ->
        s

      _ ->
        s =
          case Publisher.adapter().schedule(:x) do
            {:ok, %{days: days} = s} when map_size(days) > 0 -> s
            _ -> Publisher.default_schedule()
          end

        unless Publisher.simulated?(), do: :persistent_term.put(cache, {s, now})
        s
    end
  rescue
    _ -> Publisher.default_schedule()
  end

  @day_keys ~w(mon tue wed thu fri sat sun)

  @doc """
  The next free slot of each network after `now` (UTC): the first slot of
  the schedule not taken by a post in its queue. `%{"x" => dt, "linkedin" => dt}`.
  """
  def next_slots(now \\ DateTime.utc_now()) do
    taken = taken_slots()
    s = schedule()
    slots = upcoming_slots(s, now, 21)

    for n <- Post.networks(), into: %{} do
      {n, Enum.find(slots, &(not MapSet.member?(taken[n], &1)))}
    end
  end

  @doc "« mer. 18 nov. à 14:00 », or both slots when they differ."
  def next_slot_label(networks, now \\ DateTime.utc_now()) do
    slots = next_slots(now)

    case networks |> Enum.map(&slots[&1]) |> Enum.reject(&is_nil/1) |> Enum.uniq() do
      [] -> nil
      [one] -> Clock.label(one)
      _ -> Enum.map_join(networks, " · ", &"#{network_name(&1)} #{Clock.label(slots[&1])}")
    end
  end

  defp network_name("x"), do: "X"
  defp network_name("linkedin"), do: "LinkedIn"

  defp taken_slots do
    posts = Repo.all(from p in Post, where: p.x_state == "queued" or p.linkedin_state == "queued")

    for n <- Post.networks(), into: %{} do
      {n,
       for(
         p <- posts,
         state(p, n) == "queued",
         due = Map.get(p, key(n, "due_at")),
         into: MapSet.new(),
         do: DateTime.truncate(%{due | second: 0}, :second)
       )}
    end
  end

  # The slots of the coming `days`, in UTC, from Paris wall-clock times.
  defp upcoming_slots(%{days: days}, now, count) do
    today = now |> Clock.paris() |> NaiveDateTime.to_date()

    for offset <- 0..(count - 1),
        date = Date.add(today, offset),
        time <- Map.get(days, Enum.at(@day_keys, Date.day_of_week(date) - 1), []),
        {:ok, t} <- [Time.from_iso8601(time <> ":00")],
        slot = Clock.utc(NaiveDateTime.new!(date, t)),
        DateTime.compare(slot, DateTime.add(now, 300, :second)) == :gt,
        do: slot
  end

  @doc """
  This week's grid (Monday to Friday, or next week from Saturday): the
  schedule's times as rows, and in each cell what is due or went out then.
  `%{days: [Date], times: ["10:00"…], cells: %{{date, time} => %{kind, posts}}}`
  where kind is `:past`, `:free`, `:scheduled` or `:sent`.
  """
  def week(now \\ DateTime.utc_now()) do
    local = Clock.paris(now)
    today = NaiveDateTime.to_date(local)
    dow = Date.day_of_week(today)
    monday = if dow >= 6, do: Date.add(today, 8 - dow), else: Date.add(today, 1 - dow)
    days = for i <- 0..4, do: Date.add(monday, i)
    s = schedule()

    times =
      days
      |> Enum.flat_map(&Map.get(s.days, Enum.at(@day_keys, Date.day_of_week(&1) - 1), []))
      |> Enum.uniq()
      |> Enum.sort()

    from = Clock.utc(NaiveDateTime.new!(monday, ~T[00:00:00]))
    to = DateTime.add(from, 7, :day)

    posts =
      Repo.all(
        from p in Post,
          where:
            (p.x_due_at >= ^from and p.x_due_at < ^to) or
              (p.linkedin_due_at >= ^from and p.linkedin_due_at < ^to) or
              (p.x_sent_at >= ^from and p.x_sent_at < ^to) or
              (p.linkedin_sent_at >= ^from and p.linkedin_sent_at < ^to)
      )

    entries =
      for p <- posts,
          n <- Post.networks(),
          state(p, n) in ["queued", "sent", "simulated"],
          at = Map.get(p, key(n, "sent_at")) || Map.get(p, key(n, "due_at")),
          at,
          do: {Clock.paris(at), n, state(p, n), p}

    cells =
      for d <- days, t <- times, into: %{} do
        {:ok, time} = Time.from_iso8601(t <> ":00")
        start = NaiveDateTime.new!(d, time)
        stop = NaiveDateTime.add(start, 3600, :second)

        here =
          for {at, n, st, p} <- entries,
              NaiveDateTime.compare(at, start) != :lt and NaiveDateTime.compare(at, stop) == :lt,
              do: %{network: n, state: st, post: p}

        kind =
          cond do
            here != [] and Enum.all?(here, &(&1.state in ["sent", "simulated"])) -> :sent
            here != [] -> :scheduled
            NaiveDateTime.compare(start, local) == :lt -> :past
            true -> :free
          end

        {{d, t}, %{kind: kind, posts: here}}
      end

    %{days: days, times: times, cells: cells}
  end

  @doc "The latest post leading to a page (any of its languages), if any."
  def latest_for_page(path) do
    pattern = "%" <> path <> "?%"

    Repo.one(
      from p in Post,
        where:
          p.page_path == ^path or like(p.link_x, ^pattern) or like(p.link_linkedin, ^pattern),
        where: p.status != "rejected",
        order_by: [desc: p.inserted_at, desc: p.id],
        limit: 1
    )
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
