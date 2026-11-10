defmodule SyliAtlas.Market.Observation do
  @moduledoc """
  What one source said about one security (`subject_type` "security") or
  one exchange's main index ("index") for one session. Observations are
  only added, never replaced: consolidation picks among them.
  """
  use Ecto.Schema
  alias SyliAtlas.Market.DecimalText

  schema "market_observations" do
    field :subject_type, :string
    field :subject_id, :integer
    field :trade_date, :date
    field :source, :string
    field :close, DecimalText
    field :change, DecimalText
    field :change_pct, DecimalText
    field :volume, :integer
    field :ytd_pct, DecimalText
    field :currency, :string
    field :as_of, :utc_datetime
    field :parser_version, :integer
    field :ingested_at, :utc_datetime

    belongs_to :raw_payload, SyliAtlas.Market.RawPayload
  end
end
