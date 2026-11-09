defmodule SyliAtlas.Repo.Migrations.CreateSnapshots do
  use Ecto.Migration

  # Documents that span many areas (the home map), built once per edition
  # from the profiles so that reading one is a single row lookup.
  def change do
    create table(:snapshots) do
      add :key, :string, null: false
      add :doc, :binary, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:snapshots, [:key])
  end
end
