defmodule SyliAtlasWeb.Admin.MembersController do
  @moduledoc """
  Admin: the accounts. Promote a member (they enter the administration once
  they have a passkey), demote an administrator (never the last one),
  deactivate an account (its sessions are closed).
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Accounts

  @filters %{
    "admins" => [role: "admin"],
    "cle" => [only: :with_passkey],
    "desactives" => [only: :deactivated]
  }

  def index(conn, params) do
    filter = if Map.has_key?(@filters, params["filtre"]), do: params["filtre"], else: "tous"

    render(conn, :index,
      page_title: "Admin · Membres",
      users: Accounts.list_users([search: params["q"]] ++ Map.get(@filters, filter, [])),
      passkey_counts: passkey_counts(),
      activity: Accounts.activity(),
      stats: Accounts.stats(),
      admins: Accounts.count_admins(),
      email_failures: SyliAtlas.Admin.Emails.failures(7),
      mail: SyliAtlas.Mailer.service(),
      q: params["q"] || "",
      filter: filter,
      me: conn.assigns.current_user.id
    )
  end

  def close_sessions(conn, %{"id" => id}) do
    user = Accounts.get_user!(id)
    count = Accounts.close_sessions(user)

    conn
    |> put_flash(:info, "#{count} session(s) fermée(s) pour #{user.email}.")
    |> back()
  end

  def role(conn, %{"id" => id, "role" => role}) when role in ["admin", "member"] do
    case Accounts.set_role(Accounts.get_user!(id), role) do
      {:ok, _} ->
        conn |> put_flash(:info, "Rôle changé.") |> back()

      {:error, :last_admin} ->
        conn |> put_flash(:error, "Le dernier administrateur garde son rôle.") |> back()
    end
  end

  def active(conn, %{"id" => id, "active" => active}) do
    case Accounts.set_active(Accounts.get_user!(id), active == "true") do
      {:ok, _} ->
        conn |> put_flash(:info, "Compte mis à jour.") |> back()

      {:error, :last_admin} ->
        conn |> put_flash(:error, "Le dernier administrateur reste actif.") |> back()
    end
  end

  defp passkey_counts do
    import Ecto.Query

    SyliAtlas.Repo.all(
      from p in SyliAtlas.Accounts.Passkey, group_by: p.user_id, select: {p.user_id, count(p.id)}
    )
    |> Map.new()
  end

  defp back(conn), do: redirect(conn, to: ~p"/admin/membres")
end
