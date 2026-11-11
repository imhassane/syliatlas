defmodule SyliAtlas.Accounts.AlertDelivery do
  @moduledoc """
  What one alert said about one event: sent at once (`immediate`) or kept
  for the digest (`digest`). Unique per alert and event, so a job run twice
  never emails twice. The payload freezes what the email shows.
  """
  use Ecto.Schema

  schema "alert_deliveries" do
    belongs_to :alert, SyliAtlas.Accounts.Alert
    belongs_to :user, SyliAtlas.Accounts.User
    field :event_key, :string
    field :kind, :string
    field :payload, :map, default: %{}
    field :mode, :string
    field :sent_at, :utc_datetime
    field :digested_at, :utc_datetime

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
