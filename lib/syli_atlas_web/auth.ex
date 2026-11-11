defmodule SyliAtlasWeb.Auth do
  @moduledoc """
  The signed-in account of a browser request. The session cookie holds a
  random token (`SyliAtlas.Accounts.Sessions`); public pages carry no
  session at all, so they stay cacheable.

  Plugs: `fetch_current_user` (assigns `current_user` and
  `current_session`, possibly nil), `require_user` and `require_admin`
  (the code and a passkey, given in this session).
  """
  use SyliAtlasWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias SyliAtlas.Accounts
  alias SyliAtlas.Accounts.User
  alias SyliAtlasWeb.Paths

  @cookie_key :user_token

  def fetch_current_user(conn, _opts) do
    case conn |> get_session(@cookie_key) |> Accounts.fetch_session() do
      nil ->
        conn |> assign(:current_user, nil) |> assign(:current_session, nil)

      session ->
        conn |> assign(:current_user, session.user) |> assign(:current_session, session)
    end
  end

  @doc "Account pages: their language is the URL's, else the account's."
  def put_account_locale(conn, _opts) do
    locale =
      conn.assigns[:locale] ||
        case conn.assigns[:current_user] do
          %User{locale: locale} -> locale
          nil -> "fr"
        end

    Gettext.put_locale(SyliAtlasWeb.Gettext, locale)
    conn |> assign(:locale, locale) |> assign(:public, false)
  end

  def require_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> maybe_store_return_to()
      |> redirect(to: Paths.login(conn.assigns[:locale] || "fr"))
      |> halt()
    end
  end

  @doc """
  The administration: an administrator whose session holds both proofs.
  Signed out: to sign-in. Missing passkey proof: to the passkey step.
  Members: not found, so the administration does not show itself.
  """
  def require_admin(conn, _opts) do
    user = conn.assigns[:current_user]
    session = conn.assigns[:current_session]

    cond do
      user == nil ->
        conn |> maybe_store_return_to() |> redirect(to: Paths.login("fr")) |> halt()

      not User.admin?(user) ->
        conn |> put_status(404) |> put_view(SyliAtlasWeb.ErrorHTML) |> render(:"404") |> halt()

      not Accounts.admin_session?(user, session) ->
        conn |> maybe_store_return_to() |> redirect(to: Paths.admin_key(user.locale)) |> halt()

      true ->
        conn
    end
  end

  @doc "Opens the session in the cookie (a new cookie, against fixation)."
  def sign_in(conn, token) do
    return_to = get_session(conn, :return_to)

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> put_session(@cookie_key, token)
    |> put_session(:return_to, return_to)
  end

  def sign_out(conn) do
    if session = conn.assigns[:current_session], do: Accounts.revoke_session(session)
    conn |> configure_session(drop: true) |> assign(:current_user, nil)
  end

  @doc "Where to go after signing in: the page asked first, else the space."
  def after_sign_in_path(conn, %User{} = user) do
    case get_session(conn, :return_to) do
      "/" <> _ = path -> path
      _ -> Paths.account(user.locale)
    end
  end

  def pop_return_to(conn), do: delete_session(conn, :return_to)

  @doc "Keeps a same-site path to come back to after signing in."
  def store_return_to(conn, "/" <> rest = path) do
    if String.starts_with?(rest, "/"), do: conn, else: put_session(conn, :return_to, path)
  end

  def store_return_to(conn, _other), do: conn

  defp maybe_store_return_to(%{method: "GET"} = conn),
    do: store_return_to(conn, current_path(conn))

  defp maybe_store_return_to(conn), do: conn

  def device(conn), do: conn |> get_req_header("user-agent") |> List.first()
end
