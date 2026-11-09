defmodule SyliAtlas.Repo.Migrations.CreateAreas do
  use Ecto.Migration

  def change do
    create table(:areas) do
      add :code, :string, null: false
      add :kind, :string, null: false
      add :name_fr, :string, null: false
      add :name_en, :string, null: false
      add :slug_fr, :string, null: false
      add :slug_en, :string, null: false
      add :region_code, :string
      add :imf_code, :string
      add :search_text, :string, null: false, default: ""

      timestamps(type: :utc_datetime)
    end

    create unique_index(:areas, [:code])
    create unique_index(:areas, [:slug_fr])
    create unique_index(:areas, [:slug_en])
    create index(:areas, [:kind, :region_code])
  end
end
