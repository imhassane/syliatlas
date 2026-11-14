defmodule SyliAtlas.Repo.Migrations.CreateFxRates do
  use Ecto.Migration

  # Exchange rates of the African currencies (and the euro and the yuan),
  # one row per currency, day and source: how many units of the currency one
  # US dollar buys, as an exact decimal kept as text. Every response stays
  # raw in object storage (market_raw_payloads, dataset "fx"); the published
  # rate of a day is the primary source's, fixed pegs applied on reading.
  def change do
    create table(:fx_rates, primary_key: false) do
      add :currency, :string, null: false, primary_key: true
      add :date, :date, null: false, primary_key: true
      add :source, :string, null: false, primary_key: true
      add :rate, :string, null: false
      add :raw_payload_id, :integer
      add :inserted_at, :utc_datetime, null: false
    end

    create index(:fx_rates, [:source, :date])
  end
end
