defmodule SyliAtlas.Accounts.Sessions do
  @moduledoc """
  Signed-in browsers. The cookie holds a random token; the database keeps
  its hash, when each proof was given (code, passkey), and the browser's
  name to list it in « Security ».
  """
  import Ecto.Query

  alias SyliAtlas.Accounts.{Passkey, Secrets, Session, User}
  alias SyliAtlas.Repo

  @doc "Opens a session after a proof (`:code` or a passkey); returns its token."
  def create(%User{} = user, proof, opts \\ []) do
    now = now(opts)
    token = Secrets.generate_token()

    attrs = %Session{
      user_id: user.id,
      token_hash: Secrets.hash_token(token),
      user_agent: user_agent(opts[:user_agent]),
      expires_at: DateTime.add(now, Session.ttl_seconds()),
      last_used_at: now
    }

    attrs =
      case proof do
        :code -> %{attrs | code_verified_at: now}
        %Passkey{id: id} -> %{attrs | passkey_verified_at: now, passkey_id: id}
      end

    session = Repo.insert!(attrs)
    Repo.update_all(where(User, id: ^user.id), set: [last_sign_in_at: now])
    {token, session}
  end

  @doc "The session and its account for a cookie token, or nil."
  def fetch(token, opts \\ [])

  def fetch(token, opts) when is_binary(token) do
    now = now(opts)

    query =
      from s in Session,
        join: u in assoc(s, :user),
        where: s.token_hash == ^Secrets.hash_token(token),
        where: is_nil(s.revoked_at) and s.expires_at > ^now and is_nil(u.deactivated_at),
        preload: [user: u]

    case Repo.one(query) do
      nil -> nil
      session -> touch(session, now)
    end
  end

  def fetch(_token, _opts), do: nil

  # Renewed on use, written at most once an hour.
  defp touch(session, now) do
    if DateTime.diff(now, session.last_used_at) >= Session.touch_seconds() do
      Repo.update_all(where(Session, id: ^session.id),
        set: [last_used_at: now, expires_at: DateTime.add(now, Session.ttl_seconds())]
      )
    end

    session
  end

  @doc "Records a proof given in an open session."
  def record(%Session{} = session, proof, opts \\ []) do
    now = now(opts)

    changes =
      case proof do
        :code -> [code_verified_at: now]
        %Passkey{id: id} -> [passkey_verified_at: now, passkey_id: id]
      end

    session |> Ecto.Changeset.change(changes) |> Repo.update!()
  end

  def list(%User{id: user_id}, opts \\ []) do
    now = now(opts)

    Repo.all(
      from s in Session,
        where: s.user_id == ^user_id and is_nil(s.revoked_at) and s.expires_at > ^now,
        order_by: [desc: s.last_used_at],
        preload: :passkey
    )
  end

  def revoke(%Session{id: id}), do: revoke_where(dynamic([s], s.id == ^id))

  def revoke(%User{id: user_id}, session_id) do
    revoke_where(dynamic([s], s.id == ^session_id and s.user_id == ^user_id))
  end

  def revoke_others(%User{id: user_id}, %Session{id: keep}) do
    revoke_where(dynamic([s], s.user_id == ^user_id and s.id != ^keep))
  end

  @doc "Every session opened with a passkey: closed when the passkey is removed."
  def revoke_by_passkey(passkey_id),
    do: revoke_where(dynamic([s], s.passkey_id == ^passkey_id))

  defp revoke_where(condition) do
    {count, _} =
      Repo.update_all(from(s in Session, where: is_nil(s.revoked_at), where: ^condition),
        set: [revoked_at: DateTime.utc_now(:second)]
      )

    count
  end

  @doc "A short name of the browser and system, for « Security »."
  def device_name(nil), do: "?"

  def device_name(ua) do
    browser =
      cond do
        ua =~ "Edg/" -> "Edge"
        ua =~ "Firefox/" -> "Firefox"
        ua =~ "Chrome/" -> "Chrome"
        ua =~ "Safari/" -> "Safari"
        true -> nil
      end

    system =
      cond do
        ua =~ ~r/iPhone|iPad/ -> "iOS"
        ua =~ "Android" -> "Android"
        ua =~ "Mac OS X" -> "macOS"
        ua =~ "Windows" -> "Windows"
        ua =~ "Linux" -> "Linux"
        true -> nil
      end

    [browser, system]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
    |> then(&if &1 == "", do: "?", else: &1)
  end

  defp user_agent(nil), do: ""
  defp user_agent(ua), do: String.slice(ua, 0, 400)

  defp now(opts),
    do: opts |> Keyword.get_lazy(:now, &DateTime.utc_now/0) |> DateTime.truncate(:second)
end
