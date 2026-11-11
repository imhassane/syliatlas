defmodule SyliAtlasWeb.SessionController do
  @moduledoc """
  Sign-in pages: an email code or a passkey for everyone; for an
  administrator, the passkey step after the code (`admin_key/2`).
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Accounts
  alias SyliAtlas.Accounts.User
  alias SyliAtlasWeb.{Auth, Paths}

  def new(conn, params) do
    conn = Auth.store_return_to(conn, params["return_to"])

    if user = conn.assigns.current_user do
      redirect(conn, to: Paths.account(user.locale))
    else
      render_new(conn, nil, "")
    end
  end

  def create(conn, %{"email" => email}) do
    locale = conn.assigns.locale

    case Accounts.request_code(email, locale) do
      {:ok, code_id, email} ->
        conn
        |> put_session(:login_code, %{"id" => code_id, "email" => email})
        |> redirect(to: Paths.login_code(locale))

      {:error, reason} ->
        render_new(conn, error_message(reason), email)
    end
  end

  def code(conn, _params) do
    case get_session(conn, :login_code) do
      %{"email" => email} -> render_code(conn, email, nil)
      _ -> redirect(conn, to: Paths.login(conn.assigns.locale))
    end
  end

  def verify(conn, %{"code" => code}) do
    locale = conn.assigns.locale

    with %{"id" => id, "email" => email} <- get_session(conn, :login_code),
         {:ok, %{user: user, token: token}} <-
           Accounts.verify_code(id, email, code, locale: locale, user_agent: Auth.device(conn)) do
      conn = Auth.sign_in(conn, token)

      if User.admin?(user) do
        redirect(conn, to: Paths.admin_key(user.locale))
      else
        to = Auth.after_sign_in_path(conn, user)
        conn |> Auth.pop_return_to() |> redirect(to: to)
      end
    else
      nil ->
        redirect(conn, to: Paths.login(locale))

      {:error, reason} when reason in [:expired, :too_many_attempts, :already_used] ->
        conn
        |> delete_session(:login_code)
        |> put_flash(:error, error_message(reason))
        |> redirect(to: Paths.login(locale))

      {:error, reason} ->
        render_code(conn, get_session(conn, :login_code)["email"], error_message(reason))
    end
  end

  @doc "The administrator's second proof, or the registration of their first passkey."
  def admin_key(conn, _params) do
    user = conn.assigns.current_user
    session = conn.assigns.current_session

    cond do
      user == nil ->
        redirect(conn, to: Paths.login(conn.assigns.locale))

      not User.admin?(user) ->
        redirect(conn, to: Paths.account(user.locale))

      Accounts.admin_session?(user, session) ->
        to = admin_return(conn)
        conn |> Auth.pop_return_to() |> redirect(to: to)

      true ->
        render(conn, :admin_key,
          page_title: gettext("Administration"),
          passkeys: Accounts.list_passkeys(user),
          code_given?: session.code_verified_at != nil,
          seo: %{noindex: true}
        )
    end
  end

  def delete(conn, _params) do
    locale = conn.assigns.locale
    conn |> Auth.sign_out() |> redirect(to: Paths.home(locale))
  end

  defp admin_return(conn) do
    case get_session(conn, :return_to) do
      "/admin" <> _ = path -> path
      _ -> ~p"/admin"
    end
  end

  defp render_new(conn, error, email) do
    render(conn, :new,
      page_title: gettext("Sign in"),
      error: error,
      email: email,
      mail?: SyliAtlas.Accounts.Emails.configured?(),
      seo: %{noindex: true}
    )
  end

  defp render_code(conn, email, error) do
    render(conn, :code,
      page_title: gettext("Enter the code"),
      email: email,
      error: error,
      seo: %{noindex: true}
    )
  end

  defp error_message(:invalid_email), do: gettext("This email address does not look right.")
  defp error_message(:invalid_code), do: gettext("Wrong code. Check the last email received.")

  defp error_message(:too_many_codes),
    do: gettext("Too many codes asked for this address. Try again in an hour.")

  defp error_message(:expired), do: gettext("This code has expired. Ask for a new one.")

  defp error_message(:too_many_attempts),
    do: gettext("Too many wrong codes. Ask for a new one.")

  defp error_message(:already_used), do: gettext("This code was already used. Ask for a new one.")
  defp error_message(:deactivated), do: gettext("This account is deactivated.")

  defp error_message(:mail_not_configured),
    do: gettext("Sign-in by email is not open yet. Come back soon.")

  defp error_message(_other), do: gettext("The email could not be sent. Try again in a moment.")
end
