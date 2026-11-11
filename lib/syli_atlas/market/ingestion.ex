defmodule SyliAtlas.Market.Ingestion do
  @moduledoc """
  Fetching from sources: the daily quota of each source (checked before
  every call, never after) and the receipt of every payload kept raw.
  """
  import Ecto.Query
  require Logger
  alias SyliAtlas.Repo
  alias SyliAtlas.Market.{Catalog, RawPayload, RawStore}

  @doc """
  Reserves one call on today's quota of a source, then runs `fun`.
  Returns `{:error, :quota_exhausted}` without calling once the cap is reached.
  """
  def call(source, fun) when is_function(fun, 0) do
    case reserve(source) do
      :ok -> fun.()
      {:error, _} = error -> error
    end
  end

  def reserve(source, day \\ Date.utc_today()) do
    cap = Catalog.get!(source).daily_cap

    Repo.transaction(fn ->
      used = calls(source, day)

      if cap && used >= cap do
        Repo.rollback(:quota_exhausted)
      else
        Repo.query!(
          """
          INSERT INTO market_api_usage (source, day, calls) VALUES (?1, ?2, 1)
          ON CONFLICT(source, day) DO UPDATE SET calls = calls + 1
          """,
          [source, Date.to_iso8601(day)]
        )

        :ok
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "The source says today's quota is used up: no more calls today."
  def exhaust!(source, day \\ Date.utc_today()) do
    cap = Catalog.get!(source).daily_cap || 0

    Repo.query!(
      """
      INSERT INTO market_api_usage (source, day, calls) VALUES (?1, ?2, ?3)
      ON CONFLICT(source, day) DO UPDATE SET calls = max(calls, ?3)
      """,
      [source, Date.to_iso8601(day), cap]
    )

    :ok
  end

  def calls(source, day \\ Date.utc_today()) do
    Repo.one(
      from u in "market_api_usage",
        where: u.source == ^source and u.day == ^Date.to_iso8601(day),
        select: u.calls
    ) || 0
  end

  @doc "Keeps a response raw (object storage) and records its receipt."
  def store!(source, dataset, exchange_code, %{url: url, status: status, body: body}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    sha = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
    key = RawStore.key(source, dataset, DateTime.to_date(now), sha)

    case RawStore.put(key, body) do
      :ok -> :ok
      {:error, reason} -> raise "raw store failed for #{key}: #{inspect(reason)}"
    end

    Repo.insert!(%RawPayload{
      source: source,
      dataset: dataset,
      exchange_code: exchange_code,
      url: url,
      http_status: status,
      sha256: sha,
      bytes: byte_size(body),
      storage_key: key,
      fetched_at: now
    })
  end

  def get_payload!(id), do: Repo.get!(RawPayload, id)

  def body(%RawPayload{storage_key: key}), do: RawStore.get(key)

  def mark_parsed!(%RawPayload{} = payload, version, error \\ nil) do
    payload
    |> Ecto.Changeset.change(
      parsed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      parser_version: version,
      error: error && String.slice(error, 0, 250)
    )
    |> Repo.update!()
  end

  def recent_payloads(limit \\ 50),
    do: Repo.all(from p in RawPayload, order_by: [desc: p.id], limit: ^limit)
end
