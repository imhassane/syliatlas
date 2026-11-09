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

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
