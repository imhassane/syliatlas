defmodule SyliAtlasWeb.Plugs.AdminAuth do
  @moduledoc """
  The administration (`/admin`): an administrator account whose session
  holds both proofs, the email code and a passkey (`SyliAtlasWeb.Auth`).
  Members get a 404; admin pages are never indexed.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> put_resp_header("x-robots-tag", "noindex, nofollow")
    |> SyliAtlasWeb.Auth.fetch_current_user([])
    |> SyliAtlasWeb.Auth.require_admin([])
  end
end
