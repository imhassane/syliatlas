defmodule SyliAtlas.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  # Accounts without passwords: a 6-digit code sent by email, or a passkey
  # (WebAuthn: the device's fingerprint, face or PIN). The first account is
  # an administrator; administrators need the code AND a passkey.
  def change do
    create table(:users) do
      # Lower-cased, trimmed.
      add :email, :string, null: false
      # member | admin
      add :role, :string, null: false, default: "member"
      add :locale, :string, null: false, default: "fr"
      # weekly | monthly | never: the digest of favourites.
      add :digest, :string, null: false, default: "weekly"
      add :security_emails, :boolean, null: false, default: true
      add :last_sign_in_at, :utc_datetime
      add :deactivated_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])

    # A code sent by email. Neither the code nor the address is stored: their
    # HMAC only, so a copy of the database reveals neither.
    create table(:login_codes) do
      add :email_hash, :binary, null: false
      add :code_hash, :binary, null: false
      add :attempts, :integer, null: false, default: 0
      add :expires_at, :utc_datetime, null: false
      add :consumed_at, :utc_datetime
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:login_codes, [:email_hash, :inserted_at])

    create table(:passkeys) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :credential_id, :binary, null: false
      # The credential's public key (COSE), never a secret.
      add :public_key, :binary, null: false
      add :sign_count, :integer, null: false, default: 0
      add :name, :string, null: false
      add :last_used_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:passkeys, [:credential_id])
    create index(:passkeys, [:user_id])

    # A challenge given to the browser, used once, within 2 minutes.
    create table(:webauthn_challenges) do
      # register | sign_in | admin
      add :purpose, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all)
      add :challenge, :binary, null: false
      add :expires_at, :utc_datetime, null: false
      add :consumed_at, :utc_datetime
      timestamps(type: :utc_datetime, updated_at: false)
    end

    # The session cookie holds a random token; its SHA-256 is stored.
    create table(:user_sessions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token_hash, :binary, null: false
      # When each proof was given in this session: the administration needs both.
      add :code_verified_at, :utc_datetime
      add :passkey_verified_at, :utc_datetime
      add :passkey_id, references(:passkeys, on_delete: :nilify_all)
      add :user_agent, :string, null: false, default: ""
      add :expires_at, :utc_datetime, null: false
      add :last_used_at, :utc_datetime, null: false
      add :revoked_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_sessions, [:token_hash])
    create index(:user_sessions, [:user_id])

    create table(:favorites) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      # area (country, region) | exchange | security | comparison
      add :kind, :string, null: false
      # Area code (CIV), exchange code (BRVM), "BRVM/SNTS", or the slugs of a comparison.
      add :ref, :string, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:favorites, [:user_id, :kind, :ref])

    create table(:alerts) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      # Countries: rating_change | new_edition | indicator_above | indicator_below
      # Markets:   session_move | price_above | price_below
      add :kind, :string, null: false
      # A country (ISO3) for country alerts.
      add :area_code, :string
      # An exchange (BRVM), and a ticker for a security (nil: its index).
      add :exchange_code, :string
      add :ticker, :string
      # An IMF indicator code (PCPIPCH), for thresholds only.
      add :indicator, :string
      # Decimal, as typed (never a float).
      add :threshold, :decimal
      # immediate | weekly
      add :frequency, :string, null: false, default: "immediate"
      add :active, :boolean, null: false, default: true
      add :last_triggered_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:alerts, [:user_id])
    create index(:alerts, [:area_code, :kind])
    create index(:alerts, [:exchange_code, :kind])
  end
end
