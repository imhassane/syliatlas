defmodule SyliAtlas.Repo.Migrations.CreateCompanies do
  use Ecto.Migration

  def change do
    create table(:companies) do
      add :product, :string, null: false
      add :country, :string, null: false
      add :name, :string, null: false
      add :kind, :string, null: false
      add :owners, :string
      add :listing, :string
      add :market_href, :string
      add :source_url, :string, null: false
      add :source_name, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :excerpt, :text
      add :note, :string
      add :checked_at, :utc_datetime
      add :verified_at, :utc_datetime
      add :position, :integer, null: false, default: 0
      timestamps(type: :utc_datetime)
    end

    create unique_index(:companies, [:product, :name])
    create index(:companies, [:status])
  end
end
