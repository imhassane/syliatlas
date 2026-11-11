defmodule SyliAtlas.Admin.Emails do
  @moduledoc """
  The emails Syli Atlas sent or must send, for the admin: alert deliveries
  (immediate or kept for the digest), the digests, and the failed sends
  (Oban jobs given up or waiting for another try). Sign-in codes are not
  logged: they are sent at once and never stored.
  """
  import Ecto.Query
  alias SyliAtlas.Repo
  alias SyliAtlas.Accounts.{AlertDelivery, User}

  @email_workers ["SyliAtlas.Workers.AlertEmailWorker", "SyliAtlas.Workers.DigestEmailWorker"]

  @doc "Rows to show, newest first. Filter: :all, :sent, :failed, :digest."
  def list(filter \\ :all, limit \\ 100) do
    failed = failed_jobs(30)
    failed_deliveries = for j <- failed, id = j.args["delivery_id"], into: %{}, do: {id, j}

    deliveries =
      from(d in AlertDelivery,
        join: u in User,
        on: u.id == d.user_id,
        order_by: [desc: d.id],
        limit: ^limit,
        select: %{
          id: d.id,
          email: u.email,
          kind: d.kind,
          mode: d.mode,
          payload: d.payload,
          sent_at: d.sent_at,
          digested_at: d.digested_at,
          at: d.inserted_at
        }
      )
      |> Repo.all()
      |> Enum.map(fn d ->
        job = failed_deliveries[d.id]

        status =
          cond do
            d.sent_at -> :sent
            job -> :failed
            d.mode == "digest" and d.digested_at -> :digested
            d.mode == "digest" -> :waiting
            true -> :sending
          end

        Map.merge(d, %{
          type: :alert,
          status: status,
          error: job && error(job),
          job_id: job && job.id
        })
      end)

    digests =
      from(j in Oban.Job,
        where: j.worker == "SyliAtlas.Workers.DigestEmailWorker",
        order_by: [desc: j.id],
        limit: ^limit,
        select: %{
          id: j.id,
          args: j.args,
          state: j.state,
          errors: j.errors,
          at: j.inserted_at,
          done: j.completed_at
        }
      )
      |> Repo.all()
      |> then(fn jobs ->
        emails = user_emails(Enum.map(jobs, & &1.args["user_id"]))

        Enum.map(jobs, fn j ->
          %{
            id: "digest-#{j.id}",
            email: emails[j.args["user_id"]] || "compte supprimé",
            kind: "digest",
            mode: "digest",
            payload: %{"date" => j.args["date"]},
            type: :digest,
            status: digest_status(j.state),
            error: if(j.state in ["retryable", "discarded"], do: error(j)),
            job_id: j.id,
            sent_at: j.done,
            at: j.at
          }
        end)
      end)

    (deliveries ++ digests)
    |> Enum.filter(fn r ->
      case filter do
        :sent -> r.status == :sent
        :failed -> r.status == :failed
        :digest -> r.mode == "digest"
        _ -> true
      end
    end)
    |> Enum.sort_by(& &1.at, {:desc, DateTime})
    |> Enum.take(limit)
  end

  def stats do
    since = DateTime.add(DateTime.utc_now(), -7, :day)

    sent =
      Repo.aggregate(from(d in AlertDelivery, where: d.sent_at > ^since), :count) +
        Repo.aggregate(
          from(j in Oban.Job,
            where:
              j.worker == "SyliAtlas.Workers.DigestEmailWorker" and j.state == "completed" and
                j.completed_at > ^since
          ),
          :count
        )

    %{
      sent: sent,
      waiting:
        Repo.aggregate(
          from(d in AlertDelivery, where: d.mode == "digest" and is_nil(d.digested_at)),
          :count
        ),
      failures: failures(7),
      service: SyliAtlas.Mailer.service()
    }
  end

  @doc "Email sends that failed (given up or waiting for another try) in the last days."
  def failures(days) do
    since = DateTime.add(DateTime.utc_now(), -days, :day)

    Repo.aggregate(
      from(j in Oban.Job,
        where:
          j.worker in @email_workers and j.state in ["retryable", "discarded"] and
            j.inserted_at > ^since
      ),
      :count
    )
  end

  defp failed_jobs(days) do
    since = DateTime.add(DateTime.utc_now(), -days, :day)

    Repo.all(
      from j in Oban.Job,
        where:
          j.worker == "SyliAtlas.Workers.AlertEmailWorker" and
            j.state in ["retryable", "discarded"] and j.inserted_at > ^since,
        select: %{id: j.id, args: j.args, errors: j.errors}
    )
  end

  defp user_emails(ids) do
    ids = Enum.reject(ids, &is_nil/1)
    Repo.all(from u in User, where: u.id in ^ids, select: {u.id, u.email}) |> Map.new()
  end

  defp digest_status("completed"), do: :sent
  defp digest_status(s) when s in ["retryable", "discarded"], do: :failed
  defp digest_status(_), do: :sending

  defp error(%{errors: [_ | _] = errors}),
    do: errors |> List.last() |> Map.get("error", "") |> String.split("\n") |> hd()

  defp error(_), do: nil
end
