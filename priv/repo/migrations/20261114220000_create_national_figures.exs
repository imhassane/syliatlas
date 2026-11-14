defmodule SyliAtlas.Repo.Migrations.CreateNationalFigures do
  use Ecto.Migration

  # Figures published by the countries themselves (statistics institutes,
  # central banks, ministries), shown next to the IMF's, never merged into
  # its series (SyliAtlas.National). One row per country, indicator and
  # calendar year: the latest figure kept, with its source, the checks it
  # passed and its status.
  def change do
    create table(:national_figures) do
      add :country_code, :string, null: false
      add :indicator, :string, null: false
      # The year the IMF gives to that period (Ethiopia: 2024/25 → 2025).
      add :calendar_year, :integer, null: false
      add :period_label, :string, null: false
      # Decimal numbers stored as text, never as floats.
      add :value, :string, null: false
      add :value_lcu, :string
      add :currency, :string
      add :fx_rate, :string
      add :base_year, :string
      add :source_name, :string, null: false
      add :source_url, :string, null: false
      add :published_on, :string
      add :quote, :text
      add :extracted_by, :string, null: false, default: "manual"
      # auto_verified | pending_review | verified | rejected
      add :status, :string, null: false
      add :checks, :map, null: false, default: %{}
      add :note, :text
      add :reviewed_at, :utc_datetime
      add :reviewed_by, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:national_figures, [:country_code, :indicator, :calendar_year])
    create index(:national_figures, [:status])

    # A change of base year announced by a country: shown as a notice on its
    # pages until an IMF edition catches up.
    create table(:national_rebasings) do
      add :country_code, :string, null: false
      add :announced_on, :string, null: false
      add :old_base, :string, null: false
      add :new_base, :string, null: false
      add :level_change_pct, :string
      add :source_name, :string, null: false
      add :source_url, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:national_rebasings, [:country_code, :announced_on])
  end
end
