defmodule SyliAtlas.Repo.Migrations.CreateSovereignRatings do
  use Ecto.Migration

  # Sovereign credit ratings: one row per agency decision (a rating, its
  # outlook, the date), so the history of a country builds up. The current
  # rating of an agency is its latest decision. Every row names its source.
  def change do
    create table(:sovereign_ratings) do
      add :country_code, :string, null: false
      add :agency, :string, null: false
      add :rating, :string, null: false
      add :outlook, :string
      # ISO date, or a month (2026-10) or a year when only that is known.
      add :action_date, :string, null: false, default: ""
      add :action_type, :string
      add :needs_check, :boolean, null: false, default: false
      add :source_url, :string
      add :note, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:sovereign_ratings, [:country_code, :agency, :action_date])
    create index(:sovereign_ratings, [:country_code])
  end
end
