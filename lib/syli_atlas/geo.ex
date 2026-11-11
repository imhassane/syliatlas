defmodule SyliAtlas.Geo do
  @moduledoc "Countries, regions and aggregates."
  import Ecto.Query
  alias SyliAtlas.Repo
  alias SyliAtlas.Geo.Area

  @regions ~w(north_africa west_africa central_africa east_africa southern_africa)

  def regions, do: @regions

  def list_countries do
    Area |> where(kind: "country") |> order_by(:name_fr) |> Repo.all()
  end

  def list_areas, do: Repo.all(from a in Area, order_by: [a.kind, a.name_fr])

  def list_regions do
    Area
    |> where(kind: "region")
    |> Repo.all()
    |> Enum.sort_by(&Enum.find_index(@regions, fn r -> r == &1.code end))
  end

  def get_area_by_code(code), do: Repo.get_by(Area, code: code)

  def get_area_by_slug(slug, "fr"), do: Repo.get_by(Area, slug_fr: slug)

  def get_area_by_slug(slug, locale) when locale in ["es", "pt"] do
    case SyliAtlas.Geo.Names.code_for_slug(slug, locale) do
      nil -> Repo.get_by(Area, slug_en: slug)
      code -> get_area_by_code(code)
    end
  end

  def get_area_by_slug(slug, _locale), do: Repo.get_by(Area, slug_en: slug)

  def countries_in_region(region_code) do
    Area |> where(kind: "country", region_code: ^region_code) |> Repo.all()
  end

  @doc "Inserts or updates the reference list shipped in priv/data/areas.json."
  def seed_areas! do
    path = Application.app_dir(:syli_atlas, "priv/data/areas.json")

    path
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("areas")
    |> Enum.each(fn attrs ->
      (get_area_by_code(attrs["code"]) || %Area{})
      |> Area.changeset(attrs)
      |> Repo.insert_or_update!()
    end)
  end
end
