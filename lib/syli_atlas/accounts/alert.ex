defmodule SyliAtlas.Accounts.Alert do
  @moduledoc """
  An alert on a country: a new rating action, a new IMF edition, an IMF
  indicator crossing a threshold, or a budget law published. Or on a market: an index or a security
  moving more than a percentage in one session, or a security's close
  crossing a price. Thresholds are exact decimals.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @country_kinds ~w(rating_change new_edition indicator_above indicator_below budget_law)
  @market_kinds ~w(session_move price_above price_below)
  @kinds @country_kinds ++ @market_kinds
  @frequencies ~w(immediate weekly)
  # The IMF indicators a threshold can watch (keys of SyliAtlas.Sources.Indicators).
  @indicators ~w(real_gdp_growth inflation public_debt_pct_gdp fiscal_balance_pct_gdp
                 current_account_pct_gdp gdp_per_capita_usd unemployment)
  @max_per_user 50

  schema "alerts" do
    belongs_to :user, SyliAtlas.Accounts.User
    field :kind, :string
    field :area_code, :string
    field :exchange_code, :string
    field :ticker, :string
    field :indicator, :string
    field :threshold, :decimal
    field :frequency, :string, default: "immediate"
    field :active, :boolean, default: true
    field :last_triggered_at, :utc_datetime
    field :last_value, :decimal
    field :last_year, :integer

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds
  def market_kinds, do: @market_kinds
  def market?(%__MODULE__{kind: kind}), do: kind in @market_kinds
  def frequencies, do: @frequencies
  def indicators, do: @indicators
  def max_per_user, do: @max_per_user

  def threshold?(%__MODULE__{kind: kind}), do: kind in ~w(indicator_above indicator_below)

  def changeset(alert, attrs) do
    alert
    |> cast(attrs, [
      :kind,
      :area_code,
      :exchange_code,
      :ticker,
      :indicator,
      :threshold,
      :frequency,
      :active
    ])
    |> validate_required([:kind, :frequency])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:frequency, @frequencies)
    |> validate_subject()
    |> validate_threshold()
  end

  # A country alert names a country; a market alert an exchange, and a
  # ticker for a price. Fields of the other family are cleared.
  defp validate_subject(changeset) do
    if get_field(changeset, :kind) in @market_kinds do
      changeset
      |> put_change(:area_code, nil)
      |> update_change(:exchange_code, &(&1 && String.downcase(String.trim(&1))))
      |> update_change(:ticker, &blank_to_nil/1)
      |> validate_required([:exchange_code, :threshold])
      |> validate_format(:exchange_code, ~r/^[a-z0-9]{2,12}$/)
      |> validate_format(:ticker, ~r/^[A-Z0-9.\-]{1,20}$/)
      |> require_ticker_for_price()
      |> validate_number(:threshold, greater_than: 0)
      |> put_change(:indicator, nil)
    else
      changeset
      |> put_change(:exchange_code, nil)
      |> put_change(:ticker, nil)
      |> validate_required([:area_code])
      |> validate_format(:area_code, ~r/^[A-Z]{3}$/)
    end
  end

  defp require_ticker_for_price(changeset) do
    if get_field(changeset, :kind) in ~w(price_above price_below),
      do: validate_required(changeset, [:ticker]),
      else: changeset
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    case value |> String.trim() |> String.upcase() do
      "" -> nil
      v -> v
    end
  end

  defp validate_threshold(%Ecto.Changeset{} = changeset) do
    if get_field(changeset, :kind) in @market_kinds,
      do: changeset,
      else: country_threshold(changeset)
  end

  defp country_threshold(changeset) do
    if get_field(changeset, :kind) in ~w(indicator_above indicator_below) do
      changeset
      |> validate_required([:indicator, :threshold])
      |> validate_inclusion(:indicator, @indicators)
    else
      changeset |> put_change(:indicator, nil) |> put_change(:threshold, nil)
    end
  end
end
