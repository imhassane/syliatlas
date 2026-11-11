defmodule SyliAtlasWeb.Plugs.CanonicalHost do
  @moduledoc """
  One address per page for search engines and passkeys.

  - When `:canonical_redirect` is on (production, see `config/runtime.exs`),
    a request on any other host (the Railway address `*.up.railway.app`, a
    `www.` variant) is answered with a permanent redirect to the same path on
    the endpoint host (`PHX_HOST`). `/health` is never redirected: Railway's
    health check calls it on its own host.
  - When `:noindex` is on (the development environment, `SITE_NOINDEX=true`),
    every response carries `X-Robots-Tag: noindex, nofollow`, so a copy of the
    site is never indexed next to production. `/robots.txt` then disallows
    everything (`SitemapController.robots/2`).
  """
  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    site = Application.get_env(:syli_atlas, :site, [])
    host = SyliAtlasWeb.Endpoint.host()

    cond do
      site[:canonical_redirect] && conn.host != host && conn.request_path != "/health" ->
        redirect(conn, host)

      site[:noindex] ->
        put_resp_header(conn, "x-robots-tag", "noindex, nofollow")

      true ->
        conn
    end
  end

  defp redirect(conn, host) do
    query = if conn.query_string == "", do: "", else: "?" <> conn.query_string
    location = "https://" <> host <> conn.request_path <> query
    # 301 for reads; 308 keeps the method and body of a form sent to the old host.
    status = if conn.method in ["GET", "HEAD"], do: 301, else: 308

    conn
    |> put_resp_header("location", location)
    |> put_resp_header("cache-control", "public, max-age=86400")
    |> send_resp(status, "")
    |> halt()
  end

  @doc "Whether search engines are kept out of this environment."
  def noindex?, do: Keyword.get(Application.get_env(:syli_atlas, :site, []), :noindex, false)
end
