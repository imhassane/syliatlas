defmodule SyliAtlas.Accounts.Alert do
  @moduledoc """
  An alert on a country: a new rating action, a new IMF edition, or an IMF
  indicator crossing a threshold. Thresholds are exact decimals.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(rating_change new_edition indicator_above indicator_below)
  @frequencies ~w(immediate weekly)
  # The IMF indicators a threshold can watch (see SyliAtlas.Sources).
  @indicators ~w(NGDP_RPCH PCPIPCH GGXWDG_NGDP GGXCNL_NGDP BCA_NGDPD NGDPDPC LUR)
  @max_per_user 50

  schema "alerts" do
    belongs_to :user, SyliAtlas.Accounts.User
    field :kind, :string
    field :area_code, :string
    field :indicator, :string
    field :threshold, :decimal
    field :frequency, :string, default: "immediate"
    field :active, :boolean, default: true
    field :last_triggered_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds
  def frequencies, do: @frequencies
  def indicators, do: @indicators
  def max_per_user, do: @max_per_user

  def threshold?(%__MODULE__{kind: kind}), do: kind in ~w(indicator_above indicator_below)

  def changeset(alert, attrs) do
    alert
    |> cast(attrs, [:kind, :area_code, :indicator, :threshold, :frequency, :active])
    |> validate_required([:kind, :area_code, :frequency])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:frequency, @frequencies)
    |> validate_format(:area_code, ~r/^[A-Z]{3}$/)
    |> validate_threshold()
  end

  defp validate_threshold(changeset) do
    if get_field(changeset, :kind) in ~w(indicator_above indicator_below) do
      changeset
      |> validate_required([:indicator, :threshold])
      |> validate_inclusion(:indicator, @indicators)
    else
      changeset |> put_change(:indicator, nil) |> put_change(:threshold, nil)
    end
  end
end
