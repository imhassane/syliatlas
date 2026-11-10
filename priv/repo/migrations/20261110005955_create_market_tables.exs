defmodule SyliAtlas.Repo.Migrations.CreateMarketTables do
  use Ecto.Migration

  # Market data (stock exchanges, listed securities, daily closes).
  #
  # Our own reference (exchanges, securities, symbol mappings) is what pages
  # read; providers only feed it. Every payload fetched is kept raw (its
  # content in object storage, here only its metadata), parsed into
  # observations (one per source), checked, then consolidated into one
  # published value per security or index and session, which remembers the
  # observation it came from. Prices are exact decimals stored as text.
  def change do
    create table(:market_exchanges) do
      add :code, :string, null: false
      add :mic, :string
      add :name, :string, null: false
      add :short_name, :string, null: false
      add :city, :string
      add :currency, :string, null: false
      add :region_code, :string
      add :country_codes, {:array, :string}, null: false, default: []
      add :timezone, :string
      add :close_utc, :string
      add :index_name, :string
      add :website, :string
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:market_exchanges, [:code])

    create table(:market_securities) do
      add :exchange_id, references(:market_exchanges, on_delete: :restrict), null: false
      add :ticker, :string, null: false
      add :name, :string, null: false
      add :kind, :string, null: false, default: "equity"
      add :isin, :string
      add :country_code, :string
      add :issuer, :string
      add :currency, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:market_securities, [:exchange_id, :ticker])

    # External identifiers of our exchanges and securities, per source.
    create table(:market_symbol_mappings) do
      add :source, :string, null: false
      add :subject_type, :string, null: false
      add :external_id, :string, null: false
      add :subject_id, :integer, null: false
      add :valid_from, :date, null: false
      add :valid_to, :date

      timestamps(type: :utc_datetime)
    end

    create unique_index(
             :market_symbol_mappings,
             [:source, :subject_type, :external_id, :valid_from],
             name: :market_symbol_mappings_unique
           )

    create table(:market_source_priorities) do
      add :exchange_id, references(:market_exchanges, on_delete: :delete_all), null: false
      add :dataset, :string, null: false
      add :source, :string, null: false
      add :rank, :integer, null: false
      add :valid_from, :date, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:market_source_priorities, [:exchange_id, :dataset, :source, :valid_from],
             name: :market_source_priorities_unique
           )

    create table(:market_raw_payloads) do
      add :source, :string, null: false
      add :dataset, :string, null: false
      add :exchange_code, :string
      add :url, :string, null: false
      add :http_status, :integer, null: false
      add :sha256, :string, null: false
      add :bytes, :integer, null: false
      add :storage_key, :string, null: false
      add :fetched_at, :utc_datetime, null: false
      add :parsed_at, :utc_datetime
      add :parser_version, :integer
      add :error, :string

      timestamps(type: :utc_datetime)
    end

    create index(:market_raw_payloads, [:source, :dataset, :fetched_at])

    create table(:market_observations) do
      add :subject_type, :string, null: false
      add :subject_id, :integer, null: false
      add :trade_date, :date, null: false
      add :source, :string, null: false
      add :close, :text
      add :change, :text
      add :change_pct, :text
      add :volume, :integer
      add :ytd_pct, :text
      add :currency, :string
      add :as_of, :utc_datetime
      add :raw_payload_id, references(:market_raw_payloads, on_delete: :delete_all), null: false
      add :parser_version, :integer, null: false
      add :ingested_at, :utc_datetime, null: false
    end

    create unique_index(
             :market_observations,
             [:subject_type, :subject_id, :trade_date, :source, :raw_payload_id],
             name: :market_observations_unique
           )

    create index(:market_observations, [:raw_payload_id])

    create table(:market_eod_prices, primary_key: false) do
      add :security_id, references(:market_securities, on_delete: :delete_all), primary_key: true

      add :trade_date, :date, primary_key: true
      add :close, :text, null: false
      add :change, :text
      add :change_pct, :text
      add :volume, :integer
      add :currency, :string, null: false
      add :source, :string, null: false
      add :observation_id, :integer, null: false
      add :as_of, :utc_datetime
      add :consolidated_at, :utc_datetime, null: false
    end

    create table(:market_index_values, primary_key: false) do
      add :exchange_id, references(:market_exchanges, on_delete: :delete_all), primary_key: true
      add :trade_date, :date, primary_key: true
      add :value, :text, null: false
      add :change_pct, :text
      add :ytd_pct, :text
      add :source, :string, null: false
      add :observation_id, :integer, null: false
      add :as_of, :utc_datetime
      add :consolidated_at, :utc_datetime, null: false
    end

    create table(:market_quality_issues) do
      add :rule, :string, null: false
      add :severity, :string, null: false
      add :subject_type, :string, null: false
      add :subject_id, :integer, null: false
      add :trade_date, :date
      add :detail, :string, null: false
      add :status, :string, null: false, default: "open"
      add :data, :map, default: %{}
      add :detected_at, :utc_datetime, null: false
      add :resolved_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:market_quality_issues, [:subject_type, :subject_id, :status])
    create index(:market_quality_issues, [:status, :severity])

    # Calls made to each paying or rate-limited source, per UTC day.
    create table(:market_api_usage, primary_key: false) do
      add :source, :string, primary_key: true
      add :day, :date, primary_key: true
      add :calls, :integer, null: false, default: 0
    end
  end
end
