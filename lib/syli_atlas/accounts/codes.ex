defmodule SyliAtlas.Accounts.Codes do
  @moduledoc """
  Sign-in by a 6-digit code sent by email.

  `request/3` sends a code (5 per address and per hour); `verify/4` checks
  it and opens a session. A wrong code counts one attempt; after 5 attempts
  or 10 minutes the code is dead. A right code is consumed atomically, so
  two submissions cannot both open a session.

  The first account becomes the administrator. When `FIRST_ADMIN_EMAIL` is
  set, only that address can take the role: anyone signing up first after a
  deploy would otherwise own the administration.
  """
  import Ecto.Query

  alias SyliAtlas.Accounts.{Emails, LoginCode, Secrets, Sessions, User}
  alias SyliAtlas.Repo

  @doc "Sends a code. `{:ok, code_id, email}` or `{:error, reason}`."
  def request(raw_email, locale, opts \\ []) do
    now = now(opts)

    with {:ok, email} <- normalize(raw_email),
         email_hash = Secrets.hash_email(email),
         :ok <- check_rate(email_hash, now) do
      code = Secrets.generate_code()
      user = Repo.get_by(User, email: email)

      row =
        Repo.transaction(fn ->
          row =
            Repo.insert!(%LoginCode{
              email_hash: email_hash,
              code_hash: <<>>,
              expires_at: DateTime.add(now, LoginCode.ttl_seconds())
            })

          row
          |> Ecto.Changeset.change(code_hash: Secrets.hash_code(row.id, code))
          |> Repo.update!()
        end)
        |> elem(1)

      locale = (user && user.locale) || locale

      case Emails.deliver(Emails.code(email, code, locale, user != nil and User.admin?(user))) do
        :ok ->
          {:ok, row.id, email}

        {:error, reason} ->
          Repo.delete!(row)
          {:error, reason}
      end
    end
  end

  @doc """
  Checks a code sent to `email` and opens a session. Options: `:now`,
  `:locale` (of a new account), `:user_agent`.
  """
  def verify(code_id, raw_email, code, opts \\ []) do
    now = now(opts)

    with {:ok, email} <- normalize(raw_email),
         %LoginCode{} = row <- get(code_id),
         :ok <- LoginCode.check(row, now),
         :ok <- check_code(row, email, code) do
      consume_and_sign_in(row, email, opts, now)
    else
      nil -> {:error, :invalid_code}
      {:error, :invalid_email} -> {:error, :invalid_code}
      {:error, _} = error -> error
    end
  end

  defp get(id) do
    case Integer.parse(to_string(id)) do
      {int, ""} -> Repo.get(LoginCode, int)
      _ -> nil
    end
  end

  defp check_code(row, email, code) do
    right? =
      is_binary(code) and
        Secrets.same?(Secrets.hash_email(email), row.email_hash) and
        Secrets.same?(Secrets.hash_code(row.id, String.replace(code, ~r/\s/, "")), row.code_hash)

    if right? do
      :ok
    else
      Repo.update_all(where(LoginCode, id: ^row.id), inc: [attempts: 1])
      {:error, :invalid_code}
    end
  end

  defp consume_and_sign_in(row, email, opts, now) do
    Repo.transaction(fn ->
      {count, _} =
        Repo.update_all(from(c in LoginCode, where: c.id == ^row.id and is_nil(c.consumed_at)),
          set: [consumed_at: now]
        )

      if count != 1, do: Repo.rollback(:already_used)

      {user, new?} = find_or_create(email, Keyword.get(opts, :locale, "fr"))
      if user.deactivated_at, do: Repo.rollback(:deactivated)

      {token, session} = Sessions.create(user, :code, opts)
      %{user: user, token: token, session: session, new_account: new?}
    end)
    |> case do
      {:ok, result} ->
        if result.new_account, do: welcome(result.user)
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp find_or_create(email, locale) do
    case Repo.get_by(User, email: email) do
      %User{} = user ->
        {user, false}

      nil ->
        role = if first_admin?(email), do: "admin", else: "member"
        {email |> User.create_changeset(role, locale) |> Repo.insert!(), true}
    end
  end

  # No administrator yet, and the address is the one reserved for it (if any).
  defp first_admin?(email) do
    no_admin? = not Repo.exists?(where(User, role: "admin"))

    case Application.get_env(:syli_atlas, :first_admin_email) do
      nil -> no_admin? and not Repo.exists?(User)
      reserved -> no_admin? and reserved == email
    end
  end

  defp welcome(%User{role: "admin"} = user), do: Emails.deliver(Emails.first_admin(user))
  defp welcome(user), do: Emails.deliver(Emails.welcome(user))

  defp check_rate(email_hash, now) do
    since = DateTime.add(now, -3600)

    count =
      Repo.aggregate(
        from(c in LoginCode, where: c.email_hash == ^email_hash and c.inserted_at > ^since),
        :count
      )

    if count < LoginCode.max_per_hour(), do: :ok, else: {:error, :too_many_codes}
  end

  defp normalize(raw) do
    case User.normalize_email(raw) do
      nil -> {:error, :invalid_email}
      email -> {:ok, email}
    end
  end

  defp now(opts),
    do: opts |> Keyword.get_lazy(:now, &DateTime.utc_now/0) |> DateTime.truncate(:second)
end
