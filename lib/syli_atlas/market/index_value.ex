defmodule SyliAtlas.Market.IndexValue do
  @moduledoc "The published value of an exchange's main index for a session."
  use Ecto.Schema
  alias SyliAtlas.Market.DecimalText

  @primary_key false
  schema "market_index_values" do
    belongs_to :exchange, SyliAtlas.Market.Exchange, primary_key: true
    field :trade_date, :date, primary_key: true
    field :value, DecimalText
    field :change_pct, DecimalText
    field :ytd_pct, DecimalText
    field :source, :string
    field :observation_id, :integer
    field :as_of, :utc_datetime
    field :consolidated_at, :utc_datetime
  end
end
