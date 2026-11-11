defmodule SyliAtlas.Repo.Migrations.CreateRatingProposals do
  use Ecto.Migration

  def change do
    # Set when someone checked a decision in the admin: the bundled file no
    # longer overwrites it at start-up.
    alter table(:sovereign_ratings) do
      add :reviewed_at, :utc_datetime
    end

    # News items read by the watch, kept so each one is read only once.
    create table(:rating_watch_items) do
      add :url, :string, null: false
      add :title, :string, null: false
      add :summary, :text, default: ""
      add :feed, :string, default: ""
      add :published_at, :utc_datetime
      # new | extracted | ignored | failed
      add :status, :string, null: false, default: "new"
      add :error, :string
      timestamps(type: :utc_datetime)
    end

    create unique_index(:rating_watch_items, [:url])
    create index(:rating_watch_items, [:status])

    # Decisions waiting for a human: proposed by the watch (AI extraction) or
    # typed in the admin. Published only once approved, with the agency's release.
    create table(:rating_proposals) do
      add :country_code, :string, null: false
      add :agency, :string, null: false
      add :rating, :string, null: false
      add :outlook, :string
      add :action_date, :string, null: false, default: ""
      add :action_type, :string
      add :source_url, :string
      add :article_url, :string
      add :article_title, :string
      add :excerpt, :text
      add :origin, :string, null: false, default: "manual"
      add :warnings, {:array, :string}, default: []
      # pending | approved | rejected
      add :status, :string, null: false, default: "pending"
      add :reviewed_at, :utc_datetime
      add :watch_item_id, references(:rating_watch_items, on_delete: :nilify_all)
      timestamps(type: :utc_datetime)
    end

    create index(:rating_proposals, [:status])

    create unique_index(:rating_proposals, [:country_code, :agency, :action_date, :rating],
             where: "status = 'pending'",
             name: :rating_proposals_pending_once
           )
  end
end
