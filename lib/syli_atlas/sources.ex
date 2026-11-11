defmodule SyliAtlas.Sources do
  @moduledoc "Data sources, their editions and raw observations."
  import Ecto.Query
  alias SyliAtlas.Repo
  alias SyliAtlas.Sources.{Source, Edition, Observation}

  @sources [
    %{
      code: "imf_weo",
      name: "IMF World Economic Outlook",
      url: "https://www.imf.org/external/datamapper/api/v1",
      role: "primary",
      status: "active"
    },
    %{
      code: "world_bank_wdi",
      name: "World Bank World Development Indicators",
      url: "https://api.worldbank.org/v2",
      role: "supplement",
      status: "planned"
    },
    %{
      code: "un_wpp",
      name: "UN World Population Prospects",
      url: "https://population.un.org/dataportalapi",
      role: "supplement",
      status: "planned"
    }
  ]

  def seed_sources! do
    Enum.each(@sources, fn attrs ->
      (get_source(attrs.code) || %Source{})
      |> Source.changeset(attrs)
      |> Repo.insert_or_update!()
    end)
  end

  def list_sources, do: Repo.all(from s in Source, order_by: [s.role, s.id])
  def get_source(code), do: Repo.get_by(Source, code: code)
  def get_source!(code), do: Repo.get_by!(Source, code: code)

  def touch_source!(%Source{} = source) do
    source |> Source.changeset(%{last_checked_at: now()}) |> Repo.update!()
  end

  def get_edition(source_id, code), do: Repo.get_by(Edition, source_id: source_id, code: code)
  def get_edition!(id), do: Edition |> Repo.get!(id) |> Repo.preload(:source)

  def list_editions(limit \\ 20) do
    Edition |> order_by(desc: :id) |> limit(^limit) |> preload(:source) |> Repo.all()
  end

  @doc "The edition currently shown on the site for a source."
  def published_edition(source_code) do
    from(e in Edition,
      join: s in assoc(e, :source),
      where: s.code == ^source_code and e.status == "published",
      order_by: [desc: e.published_at],
      limit: 1,
      preload: :source
    )
    |> Repo.one()
  end

  def create_edition!(attrs), do: %Edition{} |> Edition.changeset(attrs) |> Repo.insert!()
  def update_edition!(edition, attrs), do: edition |> Edition.changeset(attrs) |> Repo.update!()

  @doc "Writes all values of an edition in one transaction, in batches."
  def insert_observations!(%Edition{id: edition_id}, rows) do
    Repo.transaction(fn ->
      Repo.delete_all(from o in Observation, where: o.edition_id == ^edition_id)

      rows
      |> Enum.map(&Map.put(&1, :edition_id, edition_id))
      |> Enum.chunk_every(500)
      |> Enum.each(&Repo.insert_all(Observation, &1))
    end)
  end

  @doc "Indicators an edition has observations for."
  def edition_indicators(%Edition{id: edition_id}) do
    from(o in Observation,
      where: o.edition_id == ^edition_id,
      distinct: true,
      select: o.indicator
    )
    |> Repo.all()
  end

  @doc "Returns %{area_code => %{indicator => %{year => value}}} for an edition."
  def observations_by_area(%Edition{id: edition_id}) do
    from(o in Observation,
      where: o.edition_id == ^edition_id,
      select: {o.area_code, o.indicator, o.year, o.value}
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {area, ind, year, value}, acc ->
      update_in(acc, [Access.key(area, %{}), Access.key(ind, %{})], &Map.put(&1, year, value))
    end)
  end

  @doc "The edition of the same source imported just before this one, with values, or nil."
  def previous_edition(%Edition{id: id, source_id: source_id}) do
    from(e in Edition,
      as: :e,
      where:
        e.source_id == ^source_id and e.id < ^id and
          e.status in ["published", "superseded"] and
          exists(from o in Observation, where: o.edition_id == parent_as(:e).id, select: 1),
      order_by: [desc: e.id],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Values that moved between two editions: `{area, indicator, year, before,
  after, change}`. Rates change in points, levels in percent; only changes
  of at least `min` (points or percent) are kept, largest first.
  """
  def revisions(%Edition{id: new_id}, %Edition{id: old_id}, min \\ 1.0, limit \\ 200) do
    rates = SyliAtlas.Sources.Indicators.rate_keys()

    from(n in Observation,
      join: o in Observation,
      on:
        o.edition_id == ^old_id and o.area_code == n.area_code and o.indicator == n.indicator and
          o.year == n.year,
      where: n.edition_id == ^new_id and not is_nil(n.value) and not is_nil(o.value),
      select: {n.area_code, n.indicator, n.year, o.value, n.value}
    )
    |> Repo.all()
    |> Enum.map(fn {area, ind, year, before, now} ->
      change =
        cond do
          ind in rates -> now - before
          before == 0 -> 0.0
          true -> (now / before - 1) * 100
        end

      %{
        area: area,
        indicator: ind,
        year: year,
        before: before,
        after: now,
        change: change,
        rate?: ind in rates
      }
    end)
    |> Enum.filter(&(abs(&1.change) >= min))
    |> Enum.sort_by(&(-abs(&1.change)))
    |> Enum.take(limit)
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
