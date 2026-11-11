defmodule SyliAtlas.Repo.Migrations.CreateApiTimings do
  use Ecto.Migration

  # Server time of the public API, one row per route and per hour (UTC),
  # shown on the API page. Durations in microseconds. No address, no query.
  def change do
    create table(:api_timings, primary_key: false) do
      add :hour, :utc_datetime, null: false, primary_key: true
      add :route, :string, null: false, primary_key: true
      add :count, :integer, null: false
      add :p50_us, :integer, null: false
      add :p95_us, :integer, null: false
      add :p99_us, :integer, null: false
      add :max_us, :integer, null: false
    end
  end
end
