defmodule SyliAtlas.Repo.Migrations.CreateBudgets do
  use Ecto.Migration

  # State budgets and the laws that vote them, for the 54 countries
  # (SyliAtlas.Budgets). Amounts are exact decimals kept as text, in the
  # country's own currency; every file read stays raw in object storage
  # (market_raw_payloads, dataset "budget").
  def change do
    # One row per country: who votes the budget and where the laws are
    # published. Seeded from priv/data/budget_catalog.json, then edited in
    # the admin (a row edited there is never overwritten by the file).
    create table(:budget_profiles, primary_key: false) do
      add :country_code, :string, null: false, primary_key: true
      add :legislature_fr, :string
      add :legislature_en, :string
      # parliament | transition | none | suspended
      add :legislature_kind, :string, null: false, default: "parliament"
      add :gazette_name, :string
      add :gazette_url, :string
      add :finance_url, :string
      # Links checked by hand: only checked links are shown publicly.
      add :verified, :boolean, null: false, default: false
      # manual (files dropped in the admin) | auto (page watched every day)
      add :collection_mode, :string, null: false, default: "manual"
      add :auto_url, :string
      add :auto_pattern, :string
      add :notes, :text
      add :edited_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    # A file read for a country's budget: fetched from the watched page or
    # dropped by an administrator. The content stays raw (raw_payload_id).
    create table(:budget_documents) do
      add :country_code, :string, null: false
      # auto | upload
      add :origin, :string, null: false
      add :url, :string
      add :filename, :string
      add :content_type, :string
      add :sha256, :string, null: false
      add :raw_payload_id, :integer
      # new | extracting | extracted | failed | no_key | ignored
      add :status, :string, null: false, default: "new"
      add :error, :string
      timestamps(type: :utc_datetime)
    end

    create unique_index(:budget_documents, [:country_code, :sha256])
    create index(:budget_documents, [:status])

    # A law waiting for a human: read from a document by the AI, or typed in
    # the admin. It becomes a budget_laws row only once approved.
    create table(:budget_proposals) do
      add :country_code, :string, null: false
      add :document_id, references(:budget_documents, on_delete: :nilify_all)
      # extraction | manual
      add :origin, :string, null: false, default: "manual"
      add :fiscal_year, :integer
      # initial | amending | settlement | provisional
      add :kind, :string
      add :sequence, :integer, null: false, default: 1
      # tabled | voted | promulgated | published
      add :stage, :string
      add :reference, :string
      add :title, :string
      add :legislature, :string
      add :tabled_on, :date
      add :voted_on, :date
      add :promulgated_on, :date
      add :published_on, :date
      add :votes_for, :integer
      add :votes_against, :integer
      add :revenue, :string
      add :expenditure, :string
      add :currency, :string
      add :source_name, :string
      add :source_url, :string
      # Where each figure was read: %{"revenue" => "p. 3", ...}
      add :evidence, :map, null: false, default: %{}
      # Results of the automatic checks: [%{"code", "level", "message"}]
      add :checks, {:array, :map}, default: []
      add :model, :string
      # pending | approved | rejected
      add :status, :string, null: false, default: "pending"
      add :reviewed_at, :utc_datetime
      add :law_id, :integer
      timestamps(type: :utc_datetime)
    end

    create index(:budget_proposals, [:status])
    create index(:budget_proposals, [:country_code])

    # The laws published on the site: one per country, year, kind and rank
    # (a year can have several amending laws).
    create table(:budget_laws) do
      add :country_code, :string, null: false
      add :fiscal_year, :integer, null: false
      add :kind, :string, null: false
      add :sequence, :integer, null: false, default: 1
      add :stage, :string, null: false
      add :reference, :string
      add :title, :string
      add :legislature, :string
      add :tabled_on, :date
      add :voted_on, :date
      add :promulgated_on, :date
      add :published_on, :date
      add :votes_for, :integer
      add :votes_against, :integer
      add :revenue, :string
      add :expenditure, :string
      add :currency, :string, null: false
      add :source_name, :string, null: false
      add :source_url, :string, null: false
      add :document_id, :integer
      add :approved_at, :utc_datetime, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:budget_laws, [:country_code, :fiscal_year, :kind, :sequence])
    create index(:budget_laws, [:approved_at])
  end
end
