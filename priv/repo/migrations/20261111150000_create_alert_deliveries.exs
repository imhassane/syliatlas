defmodule SyliAtlas.Repo.Migrations.CreateAlertDeliveries do
  use Ecto.Migration

  # What an alert sent, or keeps for the digest. One row per alert and
  # event (unique): a job run twice never emails twice.
  def change do
    alter table(:alerts) do
      # The value a threshold alert last saw: it fires when a new edition
      # crosses the threshold from this value, once.
      add :last_value, :decimal
      add :last_year, :integer
    end

    alter table(:users) do
      add :last_digest_at, :utc_datetime
    end

    create table(:alert_deliveries) do
      add :alert_id, references(:alerts, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      # "rating:CIV:moodys:2026-10-29" or "edition:2026-10".
      add :event_key, :string, null: false
      add :kind, :string, null: false
      # What the email says, frozen at the event (names, values, dates).
      add :payload, :map, null: false, default: %{}
      # immediate | digest
      add :mode, :string, null: false
      add :sent_at, :utc_datetime
      add :digested_at, :utc_datetime
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:alert_deliveries, [:alert_id, :event_key])
    create index(:alert_deliveries, [:user_id, :mode, :digested_at])
  end
end
