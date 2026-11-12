defmodule SyliAtlas.Fx.Rate do
  @moduledoc "How many units of a currency one US dollar buys on a day, according to one source."
  use Ecto.Schema
  alias SyliAtlas.Market.DecimalText

  @primary_key false
  schema "fx_rates" do
    field :currency, :string, primary_key: true
    field :date, :date, primary_key: true
    field :source, :string, primary_key: true
    field :rate, DecimalText
    field :raw_payload_id, :integer
    field :inserted_at, :utc_datetime
  end
end
