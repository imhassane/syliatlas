defmodule SyliAtlas.Market.SymbolMapping do
  @moduledoc """
  Links a source's identifier to one of our exchanges or securities, for a
  period: a ticker change closes one row and opens another.
  """
  use Ecto.Schema

  schema "market_symbol_mappings" do
    field :source, :string
    field :subject_type, :string
    field :external_id, :string
    field :subject_id, :integer
    field :valid_from, :date
    field :valid_to, :date

    timestamps(type: :utc_datetime)
  end
end
