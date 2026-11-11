defmodule SyliAtlasWeb.Plugs.ApiRateLimit do
  @moduledoc """
  Requests per minute and per visitor address (`SyliAtlasWeb.ClientIp`).

  Two counters: the public API, and the routes the site itself calls
  (`/api/internal`: search while typing, the offline pack, the version check), which
  must never eat into the public quota. Limits are read at run time:

      config :syli_atlas, SyliAtlasWeb.Plugs.ApiRateLimit,
        enabled: true, public: 60, internal: 240

  Every answer says the quota (`ratelimit-limit`, `ratelimit-remaining`);
  beyond it, 429 with `retry-after` and the usual error body.
  """
  import Plug.Conn

  @scale :timer.minutes(1)
  @internal ~w(search offline-pack offline-pages version)

  def init(opts), do: opts

  def call(conn, _opts) do
    config = Application.get_env(:syli_atlas, __MODULE__, [])

    if Keyword.get(config, :enabled, true) do
      bucket = bucket(conn)
      limit = Keyword.get(config, bucket, default(bucket))
      key = "api:#{bucket}:" <> SyliAtlasWeb.ClientIp.key(conn)

      case SyliAtlasWeb.RateLimit.hit(key, @scale, limit) do
        {:allow, count} ->
          conn
          |> put_resp_header("ratelimit-limit", Integer.to_string(limit))
          |> put_resp_header("ratelimit-remaining", Integer.to_string(max(limit - count, 0)))

        {:deny, retry_ms} ->
          conn
          |> put_resp_header("ratelimit-limit", Integer.to_string(limit))
          |> put_resp_header("ratelimit-remaining", "0")
          |> put_resp_header("retry-after", Integer.to_string(div(retry_ms, 1000) + 1))
          |> put_resp_header("cache-control", "no-store")
          |> SyliAtlasWeb.Api.Errors.send(
            429,
            "rate_limited",
            "Too many requests: try again shortly"
          )
          |> halt()
      end
    else
      conn
    end
  end

  @doc "Which counter a request uses: `:public` or `:internal`."
  def bucket(%Plug.Conn{path_info: ["api", "internal" | _]}), do: :internal

  def bucket(%Plug.Conn{path_info: ["api", "v1", route | _]}) when route in @internal,
    do: :internal

  def bucket(_conn), do: :public

  defp default(:public), do: 60
  defp default(:internal), do: 240
end
