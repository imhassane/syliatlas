defmodule SyliAtlasWeb.Plugs.ApiTiming do
  @moduledoc """
  Measures the server time of each API answer, from the router to the
  last byte handed to the web server. Sends it in `Server-Timing` (visible
  in the browser's developer tools, wherever the visitor is) and records
  it for the hourly statistics of the public routes (`SyliAtlas.ApiTimings`).
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    start = System.monotonic_time()

    register_before_send(conn, fn conn ->
      us = System.convert_time_unit(System.monotonic_time() - start, :native, :microsecond)

      if conn.status in 200..299 do
        SyliAtlas.ApiTimings.record(route(conn), us)
      end

      ms = :erlang.float_to_binary(us / 1000, decimals: 2)
      put_resp_header(conn, "server-timing", "app;desc=\"Syli Atlas\";dur=" <> ms)
    end)
  end

  @doc "The measured route of an answered request, named after its action."
  def route(conn) do
    case conn.private[:phoenix_action] do
      action when action in [:areas, :area, :csv, :compare, :ranking] -> Atom.to_string(action)
      _ -> nil
    end
  end
end
