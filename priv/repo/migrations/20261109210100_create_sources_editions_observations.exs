defmodule SyliAtlas.Repo.Migrations.CreateSourcesEditionsObservations do
  use Ecto.Migration

  def change do
    create table(:sources) do
      add :code, :string, null: false
      add :name, :string, null: false
      add :url, :string, null: false
      add :role, :string, null: false, default: "primary"
      add :status, :string, null: false, default: "active"
      add :last_checked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:sources, [:code])

    create table(:editions) do
      add :source_id, references(:sources, on_delete: :restrict), null: false
      add :code, :string, null: false
      add :label, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :fetched_at, :utc_datetime
      add :published_at, :utc_datetime
      add :checksum, :string
      add :stats, :map, default: %{}
      add :warnings, {:array, :string}, default: []

      timestamps(type: :utc_datetime)
    end

    create unique_index(:editions, [:source_id, :code])
    create index(:editions, [:status])

    create table(:observations) do
      add :edition_id, references(:editions, on_delete: :delete_all), null: false
      add :area_code, :string, null: false
      add :indicator, :string, null: false
      add :year, :integer, null: false
      add :value, :float
    end

    create unique_index(:observations, [:edition_id, :area_code, :indicator, :year])
  end
end
