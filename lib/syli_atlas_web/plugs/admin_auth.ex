defmodule SyliAtlasWeb.Plugs.AdminAuth do
  @moduledoc """
  HTTP basic authentication for `/admin`. The credentials are the Railway
  variables `ADMIN_USER` and `ADMIN_PASSWORD`, never in the code. Without
  them the admin does not exist (404). Admin pages are never indexed.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = put_resp_header(conn, "x-robots-tag", "noindex, nofollow")

    case Application.get_env(:syli_atlas, :admin, []) do
      [username: user, password: pass] when user not in [nil, ""] and pass not in [nil, ""] ->
        Plug.BasicAuth.basic_auth(conn, username: user, password: pass, realm: "Syli Atlas admin")

      _ ->
        conn |> send_resp(404, "Not Found") |> halt()
    end
  end
end
