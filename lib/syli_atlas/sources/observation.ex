defmodule SyliAtlas.Sources.Observation do
  @moduledoc "One value: an area, an indicator, a year, from one edition."
  use Ecto.Schema

  schema "observations" do
    field :area_code, :string
    field :indicator, :string
    field :year, :integer
    field :value, :float

    belongs_to :edition, SyliAtlas.Sources.Edition
  end
end
