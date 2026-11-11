defmodule SyliAtlas.Market.RawStore do
  @moduledoc """
  Where raw payloads are kept: Cloudflare R2 in production (S3 API), the
  local disk otherwise. Keys look like
  `market/mansa/stocks/2026-11-09/<sha256>.json`.
  """

  @callback put(key :: String.t(), body :: binary(), content_type :: String.t()) ::
              :ok | {:error, term()}
  @callback get(key :: String.t()) :: {:ok, binary()} | {:error, term()}

  def adapter do
    case Application.get_env(:syli_atlas, __MODULE__, [])[:adapter] do
      nil -> SyliAtlas.Market.RawStore.Local
      adapter -> adapter
    end
  end

  def put(key, body, content_type \\ "application/json"),
    do: adapter().put(key, body, content_type)

  def get(key), do: adapter().get(key)

  def key(source, dataset, date, sha256, ext \\ "json"),
    do: "market/#{source}/#{dataset}/#{Date.to_iso8601(date)}/#{sha256}.#{ext}"
end
