defmodule SyliAtlasWeb.PasskeyController do
  @moduledoc """
  The passkey ceremonies, in JSON for `assets/js/ui/passkeys.js`: options
  (a challenge), then the browser's answer. Each success answers the page
  to go to next.
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Accounts
  alias SyliAtlas.Accounts.{Emails, User}
  alias SyliAtlasWeb.{Auth, Paths}

  def sign_in_options(conn, _params), do: json(conn, Accounts.passkey_sign_in_options())

  def sign_in(conn, params) do
    case Accounts.passkey_sign_in(params, user_agent: Auth.device(conn)) do
      {:ok, %{user: user, token: token}} ->
        conn = Auth.sign_in(conn, token)
        to = Auth.after_sign_in_path(conn, user)
        conn |> Auth.pop_return_to() |> json(%{redirect: to})

      {:error, _} ->
        refuse(conn)
    end
  end

  def registration_options(conn, _params) do
    with %User{} = user <- conn.assigns.current_user,
         {:ok, options} <-
           Accounts.passkey_registration_options(user, conn.assigns.current_session) do
      json(conn, options)
    else
      _ -> refuse(conn)
    end
  end

  def register(conn, params) do
    user = conn.assigns.current_user

    with %User{} <- user,
         {:ok, passkey, _session} <-
           Accounts.register_passkey(user, conn.assigns.current_session, params) do
      device = Accounts.device_name(Auth.device(conn))
      if user.security_emails, do: Emails.deliver(Emails.passkey_added(user, passkey, device))

      to =
        if User.admin?(user), do: ~p"/admin", else: Paths.account(user.locale, :security)

      json(conn, %{redirect: to})
    else
      _ -> refuse(conn)
    end
  end

  def admin_options(conn, _params) do
    case conn.assigns.current_user do
      %User{role: "admin"} = user -> json(conn, Accounts.admin_confirm_options(user))
      _ -> refuse(conn)
    end
  end

  def admin_confirm(conn, params) do
    with %User{role: "admin"} = user <- conn.assigns.current_user,
         {:ok, passkey, session} <-
           Accounts.admin_confirm(user, conn.assigns.current_session, params),
         true <- Accounts.admin_session?(user, session) do
      device = Accounts.device_name(Auth.device(conn))

      if user.security_emails,
        do: Emails.deliver(Emails.admin_signed_in(user, passkey.name, device))

      to =
        case get_session(conn, :return_to) do
          "/admin" <> _ = path -> path
          _ -> ~p"/admin"
        end

      conn |> Auth.pop_return_to() |> json(%{redirect: to})
    else
      _ -> refuse(conn)
    end
  end

  defp refuse(conn), do: conn |> put_status(422) |> json(%{error: "invalid_passkey"})
end
