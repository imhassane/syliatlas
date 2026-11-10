defmodule SyliAtlas.Market.SourcePriority do
  @moduledoc "Which source wins, per exchange and dataset: rank 1 is published, the next ones stand in."
  use Ecto.Schema

  schema "market_source_priorities" do
    field :dataset, :string
    field :source, :string
    field :rank, :integer
    field :valid_from, :date

    belongs_to :exchange, SyliAtlas.Market.Exchange
    timestamps(type: :utc_datetime)
  end
end
