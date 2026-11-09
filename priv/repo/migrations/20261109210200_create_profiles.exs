defmodule SyliAtlas.Repo.Migrations.CreateProfiles do
  use Ecto.Migration

  # One precomputed JSONB document per area. Pages and the API read these
  # documents only, so every read is a single indexed row lookup.
  def change do
    create table(:profiles) do
      add :area_code, :string, null: false
      add :edition_id, references(:editions, on_delete: :restrict), null: false
      add :doc, :binary, null: false
      add :etag, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:profiles, [:area_code])
  end
end
