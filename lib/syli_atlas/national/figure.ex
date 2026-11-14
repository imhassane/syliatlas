defmodule SyliAtlas.National.Figure do
  @moduledoc """
  One figure published by a country: its value as published, the period it
  covers and the calendar year the IMF gives that period, the source, the
  sentence of the document it comes from, the checks it passed and its
  status (`SyliAtlas.National.Verify`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @indicators ~w(gdp_usd_bn public_debt_pct_gdp)
  @statuses ~w(auto_verified pending_review verified rejected)

  def indicators, do: @indicators
  def statuses, do: @statuses

  @doc "Statuses shown on the public pages."
  def public_statuses, do: ~w(auto_verified pending_review verified)

  @doc "Statuses that count in totals, rankings and map colours."
  def counted_statuses, do: ~w(auto_verified verified)

  schema "national_figures" do
    field :country_code, :string
    field :indicator, :string
    field :calendar_year, :integer
    field :period_label, :string
    field :value, :string
    field :value_lcu, :string
    field :currency, :string
    field :fx_rate, :string
    field :base_year, :string
    field :source_name, :string
    field :source_url, :string
    field :published_on, :string
    field :quote, :string
    field :extracted_by, :string, default: "manual"
    field :status, :string
    field :checks, :map, default: %{}
    field :note, :string
    field :reviewed_at, :utc_datetime
    field :reviewed_by, :string

    timestamps(type: :utc_datetime)
  end

  @fields ~w(country_code indicator calendar_year period_label value value_lcu currency
             fx_rate base_year source_name source_url published_on quote extracted_by
             status checks note reviewed_at reviewed_by)a

  def changeset(figure, attrs) do
    figure
    |> cast(attrs, @fields)
    |> validate_required([
      :country_code,
      :indicator,
      :calendar_year,
      :period_label,
      :value,
      :source_name,
      :source_url,
      :status
    ])
    |> validate_inclusion(:indicator, @indicators)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:extracted_by, ~w(manual ai parser))
    |> validate_number(:calendar_year,
      greater_than_or_equal_to: 2015,
      less_than_or_equal_to: 2030
    )
    |> validate_format(:value, ~r/^-?\d+(\.\d+)?$/)
    |> validate_format(:value_lcu, ~r/^-?\d+(\.\d+)?$/)
    |> validate_format(:fx_rate, ~r/^\d+(\.\d+)?$/)
    |> validate_format(:source_url, ~r{^https://})
    |> validate_format(:country_code, ~r/^[A-Z]{3}$/)
    |> unique_constraint([:country_code, :indicator, :calendar_year])
  end
end
