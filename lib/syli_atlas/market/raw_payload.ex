defmodule SyliAtlas.Market.RawPayload do
  @moduledoc """
  One response fetched from a source, kept as it came. The content lives in
  object storage under `storage_key`; this row is its receipt: where it came
  from, when, its SHA-256, and when it was parsed and by which parser.
  """
  use Ecto.Schema

  schema "market_raw_payloads" do
    field :source, :string
    field :dataset, :string
    field :exchange_code, :string
    field :url, :string
    field :http_status, :integer
    field :sha256, :string
    field :bytes, :integer
    field :storage_key, :string
    field :fetched_at, :utc_datetime
    field :parsed_at, :utc_datetime
    field :parser_version, :integer
    field :error, :string

    timestamps(type: :utc_datetime)
  end
end
