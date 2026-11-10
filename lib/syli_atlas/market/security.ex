defmodule SyliAtlas.Market.Security do
  @moduledoc "A listed share or fund, identified by its exchange and our ticker."
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(equity etf)

  schema "market_securities" do
    field :ticker, :string
    field :name, :string
    field :kind, :string, default: "equity"
    field :isin, :string
    field :country_code, :string
    field :issuer, :string
    field :currency, :string

    belongs_to :exchange, SyliAtlas.Market.Exchange
    timestamps(type: :utc_datetime)
  end

  def changeset(security, attrs) do
    security
    |> cast(attrs, [:ticker, :name, :kind, :isin, :country_code, :issuer, :currency])
    |> validate_required([:ticker, :name, :kind, :currency])
    |> validate_inclusion(:kind, @kinds)
    |> unique_constraint([:exchange_id, :ticker])
  end
end
