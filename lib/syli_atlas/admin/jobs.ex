defmodule SyliAtlas.Admin.Jobs do
  @moduledoc """
  What the admin « Mises à jour » page shows about background work: each
  Oban queue (role, schedule, waiting, done in 24 h, paused or not) and the
  latest jobs, read from the `oban_jobs` table.
  """
  import Ecto.Query
  alias SyliAtlas.Repo

  @roles %{
    "imports" => "Vérifier les sources chaque matin, importer et publier une nouvelle édition",
    "computations" => "Après une publication : alertes d'édition et mesure des lectures",
    "seo" => "Sitemap, images de partage, llms.txt",
    "alerts" => "Évaluer les alertes des membres, envoyer les e-mails et les récaps",
    "moderation" => "Discussions (pas encore ouvertes)",
    "market" => "Cours des bourses : import après les clôtures, contrôles, publication"
  }

  @workers %{
    "SyliAtlas.Workers.CheckSourcesWorker" => "Vérifier les sources",
    "SyliAtlas.Workers.ImportEditionWorker" => "Importer une édition",
    "SyliAtlas.Workers.AfterPublishWorker" => "Après publication",
    "SyliAtlas.Workers.MarketImportWorker" => "Import des bourses",
    "SyliAtlas.Workers.MarketProcessWorker" => "Traitement d'un fichier de cours",
    "SyliAtlas.Workers.MarketPublishWorker" => "Publication des bourses",
    "SyliAtlas.Workers.RatingsWatchWorker" => "Veille des notations",
    "SyliAtlas.Workers.AlertEventWorker" => "Évaluer les alertes",
    "SyliAtlas.Workers.AlertEmailWorker" => "E-mail d'alerte",
    "SyliAtlas.Workers.DigestWorker" => "Choisir les récaps du jour",
    "SyliAtlas.Workers.DigestEmailWorker" => "E-mail de récap"
  }

  def worker_label(worker),
    do: Map.get(@workers, worker, String.replace(worker, "SyliAtlas.", ""))

  @doc "Configured queues: name, concurrency, role, schedule, counts and paused state."
  def queues do
    config = Application.get_env(:syli_atlas, Oban, [])
    since = DateTime.add(DateTime.utc_now(), -24, :hour)

    waiting = counts(where(base(), [j], j.state in ["available", "scheduled", "retryable"]))
    running = counts(where(base(), [j], j.state == "executing"))
    done = counts(where(base(), [j], j.state == "completed" and j.completed_at > ^since))
    crons = crons(config)

    for {name, limit} <- config[:queues] || [] do
      name = to_string(name)

      %{
        name: name,
        role: Map.get(@roles, name, ""),
        limit: limit,
        schedule: Map.get(crons, name, []),
        waiting: Map.get(waiting, name, 0),
        running: Map.get(running, name, 0),
        done: Map.get(done, name, 0),
        paused?: paused?(name)
      }
    end
  end

  @doc "Latest jobs, newest first. Filter: :all, :failed or :running."
  def recent(filter \\ :all, limit \\ 30) do
    query =
      case filter do
        :failed -> where(base(), [j], j.state in ["retryable", "discarded"])
        :running -> where(base(), [j], j.state in ["executing", "available", "scheduled"])
        _ -> base()
      end

    query
    |> order_by([j], desc: j.id)
    |> limit(^limit)
    |> select([j], %{
      id: j.id,
      worker: j.worker,
      queue: j.queue,
      state: j.state,
      attempt: j.attempt,
      max_attempts: j.max_attempts,
      args: j.args,
      errors: j.errors,
      inserted_at: j.inserted_at,
      attempted_at: j.attempted_at,
      completed_at: j.completed_at,
      scheduled_at: j.scheduled_at
    })
    |> Repo.all()
  end

  @doc "Jobs that failed (retried or given up) in the last `days` days."
  def failures(days \\ 7) do
    since = DateTime.add(DateTime.utc_now(), -days, :day)

    base()
    |> where([j], j.state in ["retryable", "discarded"] and j.inserted_at > ^since)
    |> Repo.aggregate(:count)
  end

  @doc "The latest job of a worker whose args contain `match`, or nil."
  def latest(worker, match \\ %{}) do
    base()
    |> where([j], j.worker == ^worker)
    |> order_by([j], desc: j.id)
    |> limit(50)
    |> select([j], %{id: j.id, state: j.state, args: j.args, errors: j.errors, attempt: j.attempt})
    |> Repo.all()
    |> Enum.find(fn j -> Enum.all?(match, fn {k, v} -> j.args[to_string(k)] == v end) end)
  end

  @doc "Pauses or resumes a queue on this server (until the next restart)."
  def set_paused(queue, paused?) when is_binary(queue) do
    name = Enum.find(queue_names(), &(to_string(&1) == queue))

    cond do
      is_nil(name) -> {:error, :unknown_queue}
      paused? -> Oban.pause_queue(queue: name)
      true -> Oban.resume_queue(queue: name)
    end
  rescue
    _ -> {:error, :not_running}
  end

  @doc "The last error message of a job, or nil."
  def last_error(%{errors: [_ | _] = errors}) do
    errors |> List.last() |> Map.get("error", "") |> String.split("\n") |> hd()
  end

  def last_error(_job), do: nil

  @doc "How long a job ran, in milliseconds, or nil."
  def duration_ms(%{attempted_at: %DateTime{} = a, completed_at: %DateTime{} = c}),
    do: DateTime.diff(c, a, :millisecond)

  def duration_ms(_job), do: nil

  defp queue_names, do: Keyword.keys(Application.get_env(:syli_atlas, Oban, [])[:queues] || [])

  defp paused?(name) do
    case Oban.check_queue(queue: String.to_existing_atom(name)) do
      %{paused: paused} -> paused
      _ -> false
    end
  rescue
    _ -> false
  catch
    :exit, _ -> false
  end

  defp base, do: from(j in Oban.Job)

  defp counts(query) do
    query
    |> group_by([j], j.queue)
    |> select([j], {j.queue, count(j.id)})
    |> Repo.all()
    |> Map.new()
  end

  # %{queue => ["0 6 * * *", ...]} from the Cron plugin.
  defp crons(config) do
    (config[:plugins] || [])
    |> Enum.find_value([], fn
      {Oban.Plugins.Cron, opts} -> opts[:crontab]
      _ -> nil
    end)
    |> Enum.reduce(%{}, fn entry, acc ->
      {expr, worker} = {elem(entry, 0), elem(entry, 1)}

      queue =
        if Code.ensure_loaded?(worker) and function_exported?(worker, :__opts__, 0),
          do: to_string(worker.__opts__()[:queue] || "default"),
          else: "default"

      Map.update(acc, queue, [expr], &(&1 ++ [expr]))
    end)
  end
end
