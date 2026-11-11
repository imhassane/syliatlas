defmodule SyliAtlas.Market.EodPrice do
  @moduledoc "The published close of a security for a session, with the observation it comes from."
  use Ecto.Schema
  alias SyliAtlas.Market.DecimalText

  @primary_key false
  schema "market_eod_prices" do
    belongs_to :security, SyliAtlas.Market.Security, primary_key: true
    field :trade_date, :date, primary_key: true
    field :close, DecimalText
    field :change, DecimalText
    field :change_pct, DecimalText
    field :volume, :integer
    field :currency, :string
    field :source, :string
    field :observation_id, :integer
    field :as_of, :utc_datetime
    field :consolidated_at, :utc_datetime
  end
end
