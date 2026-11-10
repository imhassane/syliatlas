defmodule SyliAtlas.Ratings do
  @moduledoc """
  Sovereign credit ratings (S&P, Moody's, Fitch) of African countries.

  Each decision of an agency is a row of `sovereign_ratings`, with its
  source. Pages read the `ratings` document (`SyliAtlas.Ratings.Snapshot`),
  rebuilt after every change.

  Ratings are entered from the agencies' releases, never scraped from
  their sites: their terms do not allow it. The bundled file
  `priv/data/sovereign_ratings.json` is the starting point.
  """
  alias SyliAtlas.Repo
  alias SyliAtlas.Ratings.{Rating, Snapshot}

  @key "ratings"
  @doc_key {__MODULE__, :document}

  @doc "Upserts the bundled decisions, then rebuilds the document. Returns the number of rows."
  def seed! do
    path = Application.app_dir(:syli_atlas, "priv/data/sovereign_ratings.json")

    rows =
      path
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("ratings")

    Enum.each(rows, &seed_rating!/1)
    drop_stale!(rows)
    rebuild!()
    length(rows)
  end

  # A bundled row whose date was corrected in the file leaves its old copy
  # behind; remove the rows the file no longer lists, unless a person
  # checked or approved them in the admin.
  defp drop_stale!(rows) do
    import Ecto.Query

    keys = MapSet.new(rows, &{&1["country_code"], &1["agency"], &1["action_date"] || ""})

    Repo.all(from r in Rating, where: is_nil(r.reviewed_at))
    |> Enum.reject(&MapSet.member?(keys, {&1.country_code, &1.agency, &1.action_date}))
    |> Enum.each(&Repo.delete!/1)
  end

  # A decision checked in the admin wins over the bundled file.
  defp seed_rating!(attrs) do
    case get_rating(attrs["country_code"], attrs["agency"], attrs["action_date"] || "") do
      %Rating{reviewed_at: %DateTime{}} = rating ->
        rating

      existing ->
        existing |> Kernel.||(%Rating{}) |> Rating.changeset(attrs) |> Repo.insert_or_update!()
    end
  end

  defp get_rating(country_code, agency, action_date),
    do: Repo.get_by(Rating, country_code: country_code, agency: agency, action_date: action_date)

  @doc "Inserts a decision, or updates the one of the same agency, country and date."
  def put_rating!(attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    (get_rating(attrs["country_code"], attrs["agency"], attrs["action_date"] || "") ||
       %Rating{})
    |> Rating.changeset(attrs)
    |> Repo.insert_or_update!()
  end

  @doc "Rebuilds the document the pages read."
  def rebuild! do
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    Repo.query!(
      """
      INSERT INTO snapshots (key, doc, inserted_at, updated_at) VALUES (?1, jsonb(?2), ?3, ?3)
      ON CONFLICT(key) DO UPDATE SET doc = excluded.doc, updated_at = excluded.updated_at
      """,
      [@key, Jason.encode!(Snapshot.build()), now]
    )

    :persistent_term.erase(@doc_key)
    refresh_data_version()
    :ok
  end

  @doc """
  The ratings document, or nil before the first build. Kept in memory once
  read and replaced by each rebuild, so pages add no query for it (the home
  page stays at one).
  """
  def document do
    case :persistent_term.get(@doc_key, :missing) do
      :missing -> load_document()
      :none -> nil
      doc -> doc
    end
  end

  defp load_document do
    doc =
      case Repo.query!("SELECT json(doc) FROM snapshots WHERE key = ?1", [@key]).rows do
        [[json]] when is_binary(json) -> Jason.decode!(json)
        _ -> nil
      end

    :persistent_term.put(@doc_key, doc || :none)
    doc
  end

  @doc "Every decision recorded for a country, newest first."
  def history(code) do
    import Ecto.Query

    Repo.all(
      from r in Rating,
        where: r.country_code == ^code,
        order_by: [desc: r.action_date, asc: r.agency]
    )
  end

  @doc "A country's entry in the document, or nil."
  def for_country(nil, _code), do: nil
  def for_country(%{"countries" => countries}, code), do: countries[code]

  @doc "Is the stored document missing or of an older format than the code?"
  def stale? do
    case load_document() do
      %{"format" => format} -> format != Snapshot.format()
      _ -> true
    end
  end

  @version_key {__MODULE__, :data_version}

  @doc "Short identifier of the ratings online, kept in memory (page ETags)."
  def data_version do
    case :persistent_term.get(@version_key, nil) do
      nil -> refresh_data_version()
      version -> version
    end
  end

  def refresh_data_version do
    version =
      case Repo.query!("SELECT updated_at FROM snapshots WHERE key = ?1", [@key]).rows do
        [[updated_at]] -> to_string(updated_at)
        _ -> "empty"
      end

    :persistent_term.put(@version_key, version)
    version
  end
end
