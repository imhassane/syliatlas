defmodule SyliAtlas.Accounts.Digests do
  @moduledoc """
  The digest of a member's favourites, by email: every Monday or on the
  1st of the month (`User.digest`), through Oban: `DigestWorker` (cron)
  enqueues one `DigestEmailWorker` per member, retried alone if it fails.

  It holds the figures of the followed countries (watched year of the
  published IMF edition), the rating actions of the period on them, and
  the deliveries of alerts set to « in the digest ». Nothing to say, no
  email. A digest already sent today is not sent again.
  """
  import Ecto.Query

  alias SyliAtlas.Accounts.{AlertDelivery, AlertEmails, AlertRules, Emails, Favorite, User}
  alias SyliAtlas.Ratings.Rating
  alias SyliAtlas.Repo
  alias SyliAtlas.Sources
  alias SyliAtlas.Sources.Observation

  @source "imf_weo"

  @doc """
  Ids of the active members whose digest falls on `today`. A member who
  turned the digest off still gets, on Mondays, the alerts they set to
  « in the digest » (and only those).
  """
  def due_user_ids(today) do
    frequencies = Enum.filter(~w(weekly monthly), &AlertRules.digest_day?(&1, today))

    due =
      Repo.all(
        from u in User,
          where: u.digest in ^frequencies and is_nil(u.deactivated_at),
          select: u.id
      )

    alerts_only =
      if AlertRules.digest_day?("weekly", today) do
        Repo.all(
          from u in User,
            join: d in AlertDelivery,
            on: d.user_id == u.id and d.mode == "digest" and is_nil(d.digested_at),
            where: u.digest == "never" and is_nil(u.deactivated_at),
            distinct: true,
            select: u.id
        )
      else
        []
      end

    Enum.uniq(due ++ alerts_only)
  end

  @doc "Builds and sends one member's digest. `:ok`, `{:error, _}` to retry, or `{:cancel, _}`."
  def send(user_id, today) do
    with %User{deactivated_at: nil} = user <- Repo.get(User, user_id),
         false <- sent_today?(user, today),
         %{} = digest <- build(user, today) do
      email =
        user
        |> AlertEmails.digest(digest)
        |> Swoosh.Email.put_private(:idempotency_key, "digest-#{user.id}-#{today}")

      case Emails.deliver(email) do
        :ok ->
          mark_sent(user, digest)
          :ok

        {:error, :mail_not_configured} ->
          {:cancel, :mail_not_configured}

        {:error, reason} ->
          {:error, reason}
      end
    else
      _nothing_to_send -> :ok
    end
  end

  @doc "What the digest says, or nil when it would say nothing."
  def build(%User{} = user, today) do
    {from, to} = AlertRules.digest_period(user.digest, today)
    year = AlertRules.watched_year(today)
    # Digest off: only the alerts set to « in the digest ».
    countries = if user.digest == "never", do: [], else: followed_areas(user)

    digest = %{
      period: user.digest,
      from: from,
      to: to,
      year: year,
      figures: figures(countries, year),
      ratings: ratings(countries, from, to),
      deliveries: pending(user)
    }

    if digest.figures == [] and digest.ratings == [] and digest.deliveries == [],
      do: nil,
      else: digest
  end

  defp followed_areas(user) do
    Repo.all(from f in Favorite, where: f.user_id == ^user.id and f.kind == "area", select: f.ref)
  end

  # [{area_code, %{"real_gdp_growth" => d, "inflation" => d}}], countries only.
  defp figures([], _year), do: []

  defp figures(codes, year) do
    case Sources.published_edition(@source) do
      nil ->
        []

      edition ->
        Repo.all(
          from o in Observation,
            where:
              o.edition_id == ^edition.id and o.year == ^year and o.area_code in ^codes and
                o.indicator in ["real_gdp_growth", "inflation"],
            select: {o.area_code, o.indicator, o.value}
        )
        |> Enum.reject(fn {_, _, v} -> is_nil(v) end)
        |> Enum.group_by(&elem(&1, 0), fn {_, ind, v} -> {ind, AlertRules.to_decimal(v)} end)
        |> Enum.map(fn {code, pairs} ->
          {code, Map.new(pairs) |> Map.put("status", AlertRules.status(year, edition.code))}
        end)
        |> Enum.sort()
    end
  end

  defp ratings([], _from, _to), do: []

  defp ratings(codes, from, to) do
    Repo.all(
      from r in Rating,
        where:
          r.country_code in ^codes and r.action_date >= ^Date.to_iso8601(from) and
            r.action_date <= ^Date.to_iso8601(to),
        order_by: [desc: r.action_date]
    )
  end

  defp pending(user) do
    Repo.all(
      from d in AlertDelivery,
        where: d.user_id == ^user.id and d.mode == "digest" and is_nil(d.digested_at),
        order_by: [desc: d.inserted_at],
        limit: 50
    )
  end

  # `last_digest_at` holds the day of the last digest (at 00:00 UTC): a
  # retried or repeated job for that day sends nothing.
  defp sent_today?(%User{last_digest_at: nil}, _today), do: false

  defp sent_today?(%User{last_digest_at: at}, today),
    do: Date.compare(DateTime.to_date(at), today) != :lt

  defp mark_sent(user, digest) do
    now = DateTime.utc_now(:second)
    day = DateTime.new!(digest.to |> Date.add(1), ~T[00:00:00], "Etc/UTC")
    ids = Enum.map(digest.deliveries, & &1.id)

    Repo.transaction(fn ->
      Repo.update_all(where(AlertDelivery, [d], d.id in ^ids),
        set: [digested_at: now, sent_at: now]
      )

      Repo.update_all(where(User, id: ^user.id), set: [last_digest_at: day])
    end)
  end
end
