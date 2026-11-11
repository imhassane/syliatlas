defmodule SyliAtlas.Cdn do
  @moduledoc """
  Cloudflare, in front of the site. After each publication of data the API
  answers are dropped from Cloudflare's cache (purge by prefix
  `<host>/api/v1/`), so that the next visitor of each city gets the new
  figures at once; between two publications they come from the nearest
  Cloudflare city.

  Needs two Railway variables, read in `config/runtime.exs`:

    * `CLOUDFLARE_ZONE_ID`: the zone of the domain;
    * `CLOUDFLARE_API_TOKEN`: a token with the single permission
      Zone > Cache Purge on that zone.

  Without them nothing is called, and the cache rule's TTL (one day) still
  bounds how long old answers can live.

  The cache rule itself is set in the Cloudflare dashboard (Caching >
  Cache Rules), on `syliatlas.com`:

    * when: hostname equals syliatlas.com and URI path starts with
      `/api/v1/`, and URI path is not `/api/v1/search` nor `/api/v1/version`;
    * then: eligible for cache; Edge TTL: status code 200, 1 day
      (other codes not cached); Browser TTL: respect origin.
  """
  require Logger

  @api "https://api.cloudflare.com/client/v4"

  @doc "Whether the zone and the token are set."
  def configured? do
    config = config()
    present?(config[:zone_id]) and present?(config[:api_token])
  end

  @doc "Queues a purge of the API answers (done by `SyliAtlas.Workers.CachePurgeWorker`)."
  def purge_api_later do
    if configured?() do
      %{} |> SyliAtlas.Workers.CachePurgeWorker.new() |> Oban.insert()
    else
      :skipped
    end
  end

  @doc "Purges the API answers now. `:ok`, `:skipped` (not configured) or `{:error, reason}`."
  def purge_api do
    config = config()

    if configured?() do
      prefix = SyliAtlasWeb.Endpoint.host() <> "/api/v1/"

      [
        method: :post,
        url: "#{@api}/zones/#{config[:zone_id]}/purge_cache",
        auth: {:bearer, config[:api_token]},
        json: %{prefixes: [prefix]}
      ]
      |> Keyword.merge(config[:req_options] || [])
      |> Req.request()
      |> case do
        {:ok, %{status: 200, body: %{"success" => true}}} ->
          Logger.info("cdn: purged #{prefix}")
          :ok

        {:ok, %{status: status, body: body}} ->
          Logger.warning("cdn: purge refused (#{status}): #{inspect(errors(body))}")
          {:error, {:http, status}}

        {:error, reason} ->
          Logger.warning("cdn: purge failed: #{inspect(reason)}")
          {:error, reason}
      end
    else
      :skipped
    end
  end

  defp errors(%{"errors" => errors}), do: errors
  defp errors(body), do: body

  defp present?(value), do: is_binary(value) and value != ""

  defp config, do: Application.get_env(:syli_atlas, __MODULE__, [])
end
