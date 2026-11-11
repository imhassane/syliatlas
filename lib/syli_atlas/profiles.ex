defmodule SyliAtlas.Profiles do
  @moduledoc """
  Precomputed JSONB documents, one per area. They are rebuilt after each
  import and read through `SyliAtlas.Profiles.Queries`.
  """
  alias SyliAtlas.{Geo, Repo, Sources}
  alias SyliAtlas.Profiles.Builder

  @doc "Rebuilds every document from a published edition. Returns the count."
  def rebuild!(%Sources.Edition{} = edition) do
    edition = Repo.preload(edition, :source)
    observations = Sources.observations_by_area(edition)
    projection_from = edition_year(edition.code)

    meta = %{
      edition: %{
        "source" => edition.source.code,
        "id" => edition.code,
        "label" => edition.label,
        "fetched_at" =>
          edition.fetched_at && Date.to_iso8601(DateTime.to_date(edition.fetched_at))
      },
      projection_from: projection_from,
      estimate_from: projection_from - 1
    }

    docs = Builder.build(observations, Geo.list_areas(), meta)
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    Repo.transaction(fn ->
      Enum.each(docs, fn {code, doc} ->
        json = Jason.encode!(doc)

        etag =
          :crypto.hash(:sha256, json) |> Base.url_encode64(padding: false) |> binary_part(0, 16)

        Repo.query!(
          """
          INSERT INTO profiles (area_code, edition_id, doc, etag, inserted_at, updated_at)
          VALUES (?1, ?2, jsonb(?3), ?4, ?5, ?5)
          ON CONFLICT(area_code) DO UPDATE SET
            edition_id = excluded.edition_id, doc = excluded.doc,
            etag = excluded.etag, updated_at = excluded.updated_at
          """,
          [code, edition.id, json, etag, now]
        )
      end)

      SyliAtlas.Profiles.Queries.refresh_snapshots!()
    end)

    refresh_data_version()
    map_size(docs)
  end

  @version_key {__MODULE__, :data_version}

  @doc """
  A short identifier of the data currently online, used by caches (ETag,
  the page version). Kept in memory: read once, then replaced by each
  rebuild, so pages ask the database nothing for it.
  """
  def data_version do
    case :persistent_term.get(@version_key, nil) do
      nil -> refresh_data_version()
      version -> version
    end
  end

  @doc "Reads the data version from the database and keeps it in memory."
  def refresh_data_version do
    version =
      case Repo.query!("SELECT max(updated_at), count(*) FROM profiles").rows do
        [[nil, _]] -> "empty"
        [[updated_at, count]] -> "#{updated_at}-#{count}"
      end

    :persistent_term.put(@version_key, version)
    version
  end

  # "2026-10" is the October 2026 edition: projections start in 2026.
  defp edition_year(<<year::binary-size(4), _rest::binary>>), do: String.to_integer(year)
end
