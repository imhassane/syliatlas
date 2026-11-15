defmodule SyliAtlas.Repo.Migrations.RebasingWatch do
  use Ecto.Migration

  # Rebasings become an alert of their own, for any country: proposed by the
  # news watch (old base and source may be missing until a person completes
  # them), published by a person, closed once an IMF edition takes them in.
  # SQLite cannot relax NOT NULL in place: the table is rebuilt.
  def up do
    create table(:national_rebasings_new) do
      add :country_code, :string, null: false
      add :announced_on, :string, null: false
      add :old_base, :string
      add :new_base, :string, null: false
      add :level_change_pct, :string
      add :source_name, :string
      add :source_url, :string
      add :status, :string, null: false, default: "published"
      add :reference_year, :integer
      add :imf_before, :string
      add :imf_edition, :string
      add :integrated_edition, :string
      add :integrated_on, :string
      add :origin, :string, null: false, default: "manual"
      add :article_url, :string
      add :article_title, :string
      add :excerpt, :text
      add :reviewed_by, :string
      add :reviewed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    execute """
    INSERT INTO national_rebasings_new
      (id, country_code, announced_on, old_base, new_base, level_change_pct, source_name,
       source_url, inserted_at, updated_at)
    SELECT id, country_code, announced_on, old_base, new_base, level_change_pct, source_name,
       source_url, inserted_at, updated_at
    FROM national_rebasings
    """

    drop table(:national_rebasings)
    rename table(:national_rebasings_new), to: table(:national_rebasings)
    create unique_index(:national_rebasings, [:country_code, :announced_on])
    create index(:national_rebasings, [:status])

    # News items read by the rebasing watch, kept so each is read once.
    create table(:national_watch_items) do
      add :url, :string, null: false
      add :title, :string, null: false
      add :summary, :text, null: false, default: ""
      add :feed, :string, null: false, default: ""
      add :published_at, :utc_datetime
      add :status, :string, null: false, default: "new"
      add :error, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:national_watch_items, [:url])
  end

  def down do
    drop table(:national_watch_items)
    drop index(:national_rebasings, [:status])

    alter table(:national_rebasings) do
      remove :status
      remove :reference_year
      remove :imf_before
      remove :imf_edition
      remove :integrated_edition
      remove :integrated_on
      remove :origin
      remove :article_url
      remove :article_title
      remove :excerpt
      remove :reviewed_by
      remove :reviewed_at
    end
  end
end
