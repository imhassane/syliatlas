defmodule SyliAtlas.Recaps do
  @moduledoc """
  The country recap without an account: anyone can ask for a weekly or
  monthly email about the countries they choose, with an address only.

  The life of a subscription (details in `docs/recap.md`):

    1. `subscribe/2` stores the address unconfirmed (or leaves a confirmed
       one untouched) and sends one email with a confirmation link. The
       link carries the choices, signed: they apply only when it is used,
       so nobody can change the countries of an address they do not read.
    2. `confirm/1`, from that link, applies the choices and marks the
       address confirmed. Nothing else is ever sent to an unconfirmed one.
    3. Every Monday (weekly) or 1st of the month (monthly), `send/2` writes
       the recap of the chosen countries (`SyliAtlas.Recaps.Content`).
    4. Each recap carries a signed link to change the countries or the
       frequency (`update/2`) and one to stop (`unsubscribe/1`), which
       deletes the row.

  `purge_unconfirmed/1` deletes the addresses that did not confirm within
  7 days. The member digest of favourites and alerts is a different
  email (`SyliAtlas.Accounts.Digests`).
  """
  import Ecto.Query
  require Logger

  alias SyliAtlas.{Geo, Repo}
  alias SyliAtlas.Accounts.{AlertRules, Emails, User}
  alias SyliAtlas.Recaps.{Content, Subscription}
  alias SyliAtlas.Recaps.Emails, as: RecapEmails

  @confirm_salt "recap-confirm"
  @manage_salt "recap-manage"
  @confirm_max_age 7 * 24 * 3600
  @manage_max_age 400 * 24 * 3600
  @unconfirmed_days 7

  # Confirmation emails: per address and per visitor address, per hour.
  @per_email 3
  @per_ip 20
  @hour 3_600_000

  def unconfirmed_days, do: @unconfirmed_days

  @doc "The ISO codes of the countries one can choose."
  def country_codes do
    Repo.all(from a in Geo.Area, where: a.kind == "country", select: a.code)
  end

  # Subscribing ---------------------------------------------------------------

  @doc """
  Records a request and sends the confirmation email. `attrs` holds
  `"email"`, `"countries"`, `"frequency"` and `"locale"`; `opts[:ip]` is the
  visitor's address, for the rate limit only (never stored).

  Returns `{:ok, subscription}` whatever the address's state, so the answer
  never tells whether it was already subscribed; `{:error, changeset}`,
  `{:error, :rate_limited}` or `{:error, :mail_not_configured}`.
  """
  def subscribe(attrs, opts \\ []) do
    email = User.normalize_email(attrs["email"] || "")
    existing = email && Repo.get_by(Subscription, email: email)
    base = existing || %Subscription{email: email}

    changeset =
      base
      |> Ecto.Changeset.change(email: email)
      |> Subscription.choices_changeset(attrs, country_codes())
      |> require_email(email)

    with {:ok, _} <- valid(changeset),
         :ok <- rate_limit(email, opts[:ip]),
         {:ok, subscription} <- store(existing, changeset) do
      choices = Ecto.Changeset.apply_changes(changeset)

      case Emails.deliver(
             RecapEmails.confirmation(
               subscription,
               choices,
               confirm_token(subscription.id, choices)
             )
           ) do
        :ok -> {:ok, subscription}
        {:error, :mail_not_configured} -> {:error, :mail_not_configured}
        {:error, _reason} -> {:error, :not_sent}
      end
    end
  end

  defp require_email(changeset, nil), do: Ecto.Changeset.add_error(changeset, :email, "invalid")
  defp require_email(changeset, _email), do: changeset

  defp valid(%Ecto.Changeset{valid?: true} = cs), do: {:ok, cs}
  defp valid(cs), do: {:error, %{cs | action: :insert}}

  # A new address is stored unconfirmed with its choices; an unconfirmed one
  # takes the new choices; a confirmed one keeps its own until the link.
  defp store(nil, changeset), do: Repo.insert(changeset)
  defp store(%Subscription{confirmed_at: nil}, changeset), do: Repo.update(changeset)
  defp store(%Subscription{} = confirmed, _changeset), do: {:ok, confirmed}

  defp rate_limit(email, ip) do
    with {:allow, _} <- SyliAtlasWeb.RateLimit.hit("recap:email:" <> email, @hour, @per_email),
         {:allow, _} <- hit_ip(ip) do
      :ok
    else
      {:deny, _retry} -> {:error, :rate_limited}
    end
  end

  defp hit_ip(nil), do: {:allow, 0}
  defp hit_ip(ip), do: SyliAtlasWeb.RateLimit.hit("recap:ip:" <> ip, @hour, @per_ip)

  # Tokens --------------------------------------------------------------------

  @doc "The confirmation token: the subscription and the choices to apply."
  def confirm_token(id, %{countries: countries, frequency: frequency, locale: locale}) do
    Phoenix.Token.sign(SyliAtlasWeb.Endpoint, @confirm_salt, %{
      "id" => id,
      "countries" => countries,
      "frequency" => frequency,
      "locale" => locale
    })
  end

  @doc "The token of the links to change or stop a recap."
  def manage_token(%Subscription{id: id}),
    do: Phoenix.Token.sign(SyliAtlasWeb.Endpoint, @manage_salt, id)

  def confirm_path(token), do: "/recap/confirm/" <> token
  def manage_path(token), do: "/recap/manage/" <> token
  def stop_path(token), do: "/recap/stop/" <> token

  @doc "What a confirmation link would do: `{:ok, subscription, choices}` or `:error`."
  def resolve_confirmation(token) do
    with {:ok, %{"id" => id} = choices} <-
           Phoenix.Token.verify(SyliAtlasWeb.Endpoint, @confirm_salt, token,
             max_age: @confirm_max_age
           ),
         %Subscription{} = sub <- Repo.get(Subscription, id) do
      {:ok, sub, choices}
    else
      _ -> :error
    end
  end

  @doc "Applies a confirmation link. Idempotent: `{:ok, subscription}` or `:error`."
  def confirm(token) do
    with {:ok, sub, choices} <- resolve_confirmation(token) do
      sub
      |> Ecto.Changeset.change(email: sub.email)
      |> Subscription.choices_changeset(choices, country_codes())
      |> Ecto.Changeset.put_change(
        :confirmed_at,
        sub.confirmed_at || DateTime.utc_now(:second)
      )
      |> Repo.update()
      |> case do
        {:ok, sub} -> {:ok, sub}
        {:error, _} -> :error
      end
    end
  end

  @doc "The subscription of a change or stop link, or `:error`."
  def resolve_manage(token) do
    with {:ok, id} <-
           Phoenix.Token.verify(SyliAtlasWeb.Endpoint, @manage_salt, token,
             max_age: @manage_max_age
           ),
         %Subscription{} = sub <- Repo.get(Subscription, id) do
      {:ok, sub}
    else
      _ -> :error
    end
  end

  @doc "Changes the countries or the frequency of a confirmed subscription."
  def update(%Subscription{} = sub, attrs) do
    sub
    |> Subscription.choices_changeset(
      Map.take(attrs, ["countries", "frequency"]),
      country_codes()
    )
    |> Repo.update()
  end

  @doc """
  Stops a recap: the row is deleted. `{:ok, locale}`; `{:ok, nil}` when it
  was already gone (a second click); `:error` for a forged token.
  """
  def unsubscribe(token) do
    case Phoenix.Token.verify(SyliAtlasWeb.Endpoint, @manage_salt, token,
           max_age: @manage_max_age
         ) do
      {:ok, id} ->
        case Repo.get(Subscription, id) do
          nil ->
            {:ok, nil}

          sub ->
            Repo.delete!(sub)
            {:ok, sub.locale}
        end

      _ ->
        :error
    end
  end

  @doc "Deletes the addresses that did not confirm within #{@unconfirmed_days} days."
  def purge_unconfirmed(now \\ DateTime.utc_now()) do
    limit = DateTime.add(now, -@unconfirmed_days * 24 * 3600, :second)

    {count, _} =
      Repo.delete_all(
        from s in Subscription, where: is_nil(s.confirmed_at) and s.updated_at < ^limit
      )

    count
  end

  # Sending -------------------------------------------------------------------

  @doc "Ids of the confirmed subscriptions due `today` and not yet sent."
  def due_ids(today) do
    frequencies = Enum.filter(Subscription.frequencies(), &AlertRules.digest_day?(&1, today))

    Repo.all(
      from s in Subscription,
        where:
          not is_nil(s.confirmed_at) and s.frequency in ^frequencies and
            (is_nil(s.last_sent_on) or s.last_sent_on < ^today),
        select: s.id
    )
  end

  @doc "Builds and sends one recap. `:ok`, `{:error, _}` to retry, or `{:cancel, _}`."
  def send(id, today) do
    with %Subscription{confirmed_at: %DateTime{}} = sub <- Repo.get(Subscription, id),
         true <- sub.last_sent_on == nil or Date.compare(sub.last_sent_on, today) == :lt,
         [_ | _] <- sub.countries do
      {from, to} = AlertRules.digest_period(sub.frequency, today)
      content = Content.build(sub.countries, from, to, sub.locale)

      email =
        sub
        |> RecapEmails.recap(content, manage_token(sub))
        |> Swoosh.Email.put_private(:idempotency_key, "recap-#{sub.id}-#{today}")

      case Emails.deliver(email) do
        :ok ->
          Repo.update_all(where(Subscription, id: ^sub.id), set: [last_sent_on: today])
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
end
