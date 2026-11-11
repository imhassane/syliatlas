defmodule SyliAtlas.Repo.Migrations.CreateSearchMisses do
  use Ecto.Migration

  # Searches that found nothing, counted, so that names people type can be
  # added to the index. The normalised query only: no IP, no session.
  def change do
    create table(:search_misses) do
      add :query, :string, null: false
      add :locale, :string, null: false
      add :count, :integer, null: false, default: 1
      add :last_seen_at, :utc_datetime, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:search_misses, [:query, :locale])
  end
end
