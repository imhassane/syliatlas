defmodule SyliAtlas.Market.Exchange do
  @moduledoc """
  A stock exchange, in our own reference. `code` is ours and goes in URLs
  (`brvm`, `ngx`); `mic` is the ISO 10383 code when known. Regional
  exchanges list the countries they serve in `country_codes`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "market_exchanges" do
    field :code, :string
    field :mic, :string
    field :name, :string
    field :short_name, :string
    field :city, :string
    field :currency, :string
    field :region_code, :string
    field :country_codes, {:array, :string}, default: []
    field :timezone, :string
    field :close_utc, :string
    field :index_name, :string
    field :website, :string
    field :position, :integer, default: 0

    has_many :securities, SyliAtlas.Market.Security
    timestamps(type: :utc_datetime)
  end

  @fields ~w(code mic name short_name city currency region_code country_codes timezone close_utc index_name website position)a

  def changeset(exchange, attrs) do
    exchange
    |> cast(attrs, @fields)
    |> validate_required([:code, :name, :short_name, :currency])
    |> validate_format(:code, ~r/^[a-z0-9-]+$/)
    |> unique_constraint(:code)
  end
end
