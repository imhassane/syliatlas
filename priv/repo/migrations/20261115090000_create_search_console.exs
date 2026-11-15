defmodule SyliAtlas.Repo.Migrations.CreateSearchConsole do
  use Ecto.Migration

  # Google Search Console, imported each day (SyliAtlas.SearchConsole): for
  # each day, one row per value of a dimension (query, page, device,
  # country). Clicks and impressions are counts; position is Google's
  # average. Nothing about readers: these are Google's aggregates.
  #
  # Translation reviews: a page of another language read by a native speaker,
  # with the date; a page changed after it goes back to « to review ».
  def change do
    create table(:search_console_rows, primary_key: false) do
      add :date, :date, null: false, primary_key: true
      add :dimension, :string, null: false, primary_key: true
      add :key, :string, null: false, primary_key: true
      add :clicks, :integer, null: false, default: 0
      add :impressions, :integer, null: false, default: 0
      add :position, :float
      add :inserted_at, :utc_datetime, null: false
    end

    create index(:search_console_rows, [:dimension, :date])

    create table(:translation_reviews, primary_key: false) do
      add :path, :string, null: false, primary_key: true
      add :reviewer, :string, null: false
      add :reviewed_at, :utc_datetime, null: false
    end
  end
end
