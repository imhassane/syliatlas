defmodule SyliAtlas.Market.QualityIssue do
  @moduledoc """
  Something a check found in the data: a missing index, a session that
  never came, a suspicious change. One open issue per rule and subject; it
  says what the reader sees meanwhile (badge, hidden figure).
  """
  use Ecto.Schema

  schema "market_quality_issues" do
    field :rule, :string
    field :severity, :string
    field :subject_type, :string
    field :subject_id, :integer
    field :trade_date, :date
    field :detail, :string
    field :status, :string, default: "open"
    field :data, :map, default: %{}
    field :detected_at, :utc_datetime
    field :resolved_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
