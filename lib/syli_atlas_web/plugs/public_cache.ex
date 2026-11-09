defmodule SyliAtlasWeb.Plugs.PublicCache do
  @moduledoc """
  Cache headers for public pages and API answers. Browsers and the CDN may
  keep an answer for an hour and serve it stale for a day while they
  revalidate; the ETag follows the data version, so a revalidation after a
  new IMF edition gets fresh figures and otherwise a cheap 304.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    etag =
      ~s(W/"#{:erlang.phash2({SyliAtlas.Profiles.data_version(), conn.request_path, conn.query_string})}")

    conn =
      conn
      |> put_resp_header("cache-control", "public, max-age=3600, stale-while-revalidate=86400")
      |> put_resp_header("etag", etag)

    if etag in get_req_header(conn, "if-none-match") do
      conn |> send_resp(304, "") |> halt()
    else
      conn
    end
  end
end
