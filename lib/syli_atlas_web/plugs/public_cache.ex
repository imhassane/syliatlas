defmodule SyliAtlasWeb.Plugs.PublicCache do
  @moduledoc """
  Cache headers for public pages and API answers.

  Pages: `no-cache`, so the browser asks every time and gets a cheap 304
  while nothing changed. Their ETag follows the code and the data
  (`SyliAtlasWeb.Build.version/0`), so a deploy or a new IMF edition is
  seen at once. Offline reading is the service worker's job (`/sw.js`).

  API answers: kept an hour, served stale for a day while revalidating;
  their ETag follows the data only.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    api? = match?(["api" | _], conn.path_info)
    version = if api?, do: SyliAtlas.Profiles.data_version(), else: SyliAtlasWeb.Build.version()
    etag = ~s(W/"#{:erlang.phash2({version, conn.request_path, conn.query_string})}")

    cache =
      if api?,
        do: "public, max-age=3600, stale-while-revalidate=86400",
        else: "public, no-cache"

    conn =
      conn
      |> put_resp_header("cache-control", cache)
      |> put_resp_header("etag", etag)

    if etag in get_req_header(conn, "if-none-match") do
      conn |> send_resp(304, "") |> halt()
    else
      conn
    end
  end
end
