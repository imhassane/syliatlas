defmodule SyliAtlas.Repo.Migrations.CreateRecapSubscriptions do
  use Ecto.Migration

  # The country recap without an account (docs/recap.md). One row per
  # address: what it asked for, and whether it confirmed. Unsubscribing
  # deletes the row; an address that never confirms is deleted after 7 days.
  # Nothing else is kept: no name, no IP address, no open or click tracking.
  def change do
    create table(:recap_subscriptions) do
      # Lower-cased and trimmed (SyliAtlas.Accounts.User.normalize_email/1).
      add :email, :string, null: false
      # ISO codes of the chosen countries, in the order they were picked.
      add :countries, {:array, :string}, null: false, default: []
      # weekly (Mondays) | monthly (the 1st)
      add :frequency, :string, null: false, default: "weekly"
      # fr | en: the language of every email to this address.
      add :locale, :string, null: false, default: "fr"
      # nil until the link of the confirmation email is used: nothing is
      # sent to an unconfirmed address but that one email.
      add :confirmed_at, :utc_datetime
      # The day of the last recap (00:00 UTC): a job run twice sends once.
      add :last_sent_on, :date
      timestamps(type: :utc_datetime)
    end

    create unique_index(:recap_subscriptions, [:email])
    create index(:recap_subscriptions, [:confirmed_at, :frequency])
  end
end
