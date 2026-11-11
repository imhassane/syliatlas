defmodule SyliAtlas.Geo.Area do
  @moduledoc """
  A place the platform publishes figures for: a country, an African Union
  region, the whole continent, or an IMF aggregate (Sub-Saharan Africa, World).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(country region continent imf_aggregate)

  schema "areas" do
    field :code, :string
    field :kind, :string
    field :name_fr, :string
    field :name_en, :string
    field :slug_fr, :string
    field :slug_en, :string
    field :region_code, :string
    field :imf_code, :string
    field :search_text, :string, default: ""

    timestamps(type: :utc_datetime)
  end

  def changeset(area, attrs) do
    area
    |> cast(attrs, [:code, :kind, :name_fr, :name_en, :slug_fr, :slug_en, :region_code, :imf_code])
    |> validate_required([:code, :kind, :name_fr, :name_en, :slug_fr, :slug_en])
    |> validate_inclusion(:kind, @kinds)
    |> put_search_text()
    |> unique_constraint(:code)
  end

  def name(%__MODULE__{name_fr: name}, "fr"), do: name
  def name(%__MODULE__{name_en: name}, "en"), do: name

  def name(%__MODULE__{code: code, name_en: name}, locale),
    do: SyliAtlas.Geo.Names.name(code, locale) || name

  def slug(%__MODULE__{slug_fr: slug}, "fr"), do: slug

  def slug(%__MODULE__{code: code, slug_en: slug}, locale) when locale in ["es", "pt"],
    do: SyliAtlas.Geo.Names.slug(code, locale) || slug

  def slug(%__MODULE__{slug_en: slug}, _locale), do: slug

  @doc "Names in every language of the site, as the documents store them."
  def names(area), do: SyliAtlas.Locales.each(&name(area, &1))

  @doc "Slugs in every language of the site."
  def slugs(area), do: SyliAtlas.Locales.each(&slug(area, &1))

  defp put_search_text(changeset) do
    text =
      [:name_fr, :name_en, :code]
      |> Enum.map(&(get_field(changeset, &1) || ""))
      |> Enum.join(" ")
      |> normalize()

    put_change(changeset, :search_text, text)
  end

  @doc "Lower-cases and strips accents so that searches ignore them."
  def normalize(text) do
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
  end
end
