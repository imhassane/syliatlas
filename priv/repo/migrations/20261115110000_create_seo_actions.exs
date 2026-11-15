defmodule SyliAtlas.Repo.Migrations.CreateSeoActions do
  use Ecto.Migration

  # « To do this week » on /admin/recherche-google: a first-page query
  # without a click that an admin marked as handled (title rewritten…), with
  # who and when. Reopening deletes the row.
  def change do
    create table(:seo_actions, primary_key: false) do
      add :query, :string, null: false, primary_key: true
      add :done_by, :string, null: false
      add :done_at, :utc_datetime, null: false
    end
  end
end
