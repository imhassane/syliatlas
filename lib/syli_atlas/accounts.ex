defmodule SyliAtlas.Accounts do
  @moduledoc """
  Accounts without passwords. A member signs in with a code sent by email
  or with a passkey (fingerprint, face, device PIN). The first account is
  the administrator; the administration needs both proofs, given in the
  same session within 8 hours (`SyliAtlas.Accounts.Session`).

  Members keep favourites and alerts in their space.
  """
  import Ecto.Query

  alias SyliAtlas.Accounts.{Alerts, Codes, Favorites, Passkeys, Session, Sessions, User}
  alias SyliAtlas.Repo

  defdelegate request_code(email, locale, opts \\ []), to: Codes, as: :request
  defdelegate verify_code(code_id, email, code, opts \\ []), to: Codes, as: :verify

  defdelegate passkey_sign_in_options(), to: Passkeys, as: :sign_in_options
  defdelegate passkey_sign_in(params, opts \\ []), to: Passkeys, as: :sign_in

  defdelegate passkey_registration_options(user, session, opts \\ []),
    to: Passkeys,
    as: :registration_options

  defdelegate register_passkey(user, session, params, opts \\ []), to: Passkeys, as: :register
  defdelegate admin_confirm_options(user), to: Passkeys, as: :confirm_options
  defdelegate admin_confirm(user, session, params, opts \\ []), to: Passkeys, as: :confirm
  defdelegate list_passkeys(user), to: Passkeys, as: :list
  defdelegate remove_passkey(user, id), to: Passkeys, as: :remove

  defdelegate fetch_session(token, opts \\ []), to: Sessions, as: :fetch
  defdelegate list_sessions(user), to: Sessions, as: :list
  defdelegate revoke_session(session), to: Sessions, as: :revoke
  defdelegate revoke_session(user, session_id), to: Sessions, as: :revoke
  defdelegate revoke_other_sessions(user, session), to: Sessions, as: :revoke_others
  defdelegate device_name(user_agent), to: Sessions

  defdelegate list_favorites(user), to: Favorites, as: :list
  defdelegate favorite_keys(user), to: Favorites, as: :keys
  defdelegate add_favorite(user, kind, ref), to: Favorites, as: :add
  defdelegate remove_favorite(user, kind, ref), to: Favorites, as: :remove

  defdelegate list_alerts(user), to: Alerts, as: :list
  defdelegate get_alert(user, id), to: Alerts, as: :get

  defdelegate change_alert(alert \\ %SyliAtlas.Accounts.Alert{}, attrs \\ %{}),
    to: Alerts,
    as: :change

  defdelegate create_alert(user, attrs), to: Alerts, as: :create
  defdelegate update_alert(alert, attrs), to: Alerts, as: :update
  defdelegate delete_alert(user, id), to: Alerts, as: :delete

  @doc "Whether this session may enter the administration."
  def admin_session?(%User{role: "admin"}, %Session{} = session),
    do: Session.admin_verified?(session, DateTime.utc_now())

  def admin_session?(_user, _session), do: false

  def update_preferences(%User{} = user, attrs),
    do: user |> User.preferences_changeset(attrs) |> Repo.update()

  @doc "Deletes an account and everything attached to it."
  def delete_account(%User{role: "admin"} = user) do
    if count_admins() <= 1, do: {:error, :last_admin}, else: Repo.delete(user)
  end

  def delete_account(%User{} = user), do: Repo.delete(user)

  # Administration ---------------------------------------------------------

  def list_users(opts \\ []) do
    query = from u in User, order_by: [desc: u.inserted_at], limit: 200

    query =
      case opts[:search] do
        q when is_binary(q) and q != "" -> where(query, [u], like(u.email, ^"%#{q}%"))
        _ -> query
      end

    query = if opts[:role], do: where(query, [u], u.role == ^opts[:role]), else: query
    Repo.all(query)
  end

  def get_user!(id), do: Repo.get!(User, id)

  def count_admins, do: Repo.aggregate(where(User, role: "admin"), :count)

  def stats do
    %{
      users: Repo.aggregate(User, :count),
      with_passkey:
        Repo.one(from p in SyliAtlas.Accounts.Passkey, select: count(p.user_id, :distinct)),
      alerts: Repo.aggregate(where(SyliAtlas.Accounts.Alert, active: true), :count)
    }
  end

  @doc """
  Gives or removes the administrator role. The last administrator keeps it.
  A new administrator enters the administration once they have a passkey.
  """
  def set_role(%User{} = user, role) when role in ["member", "admin"] do
    if user.role == "admin" and role == "member" and count_admins() <= 1 do
      {:error, :last_admin}
    else
      user |> Ecto.Changeset.change(role: role) |> Repo.update()
    end
  end

  def set_active(%User{} = user, active?) do
    if not active? and user.role == "admin" and count_admins() <= 1 do
      {:error, :last_admin}
    else
      at = if active?, do: nil, else: DateTime.utc_now(:second)
      {:ok, user} = user |> Ecto.Changeset.change(deactivated_at: at) |> Repo.update()

      unless active?,
        do: Repo.update_all(where(Session, user_id: ^user.id), set: [revoked_at: at])

      {:ok, user}
    end
  end
end
