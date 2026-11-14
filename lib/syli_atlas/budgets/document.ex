defmodule SyliAtlas.Budgets.Document do
  @moduledoc """
  A file read for a country's budget, fetched from a watched page or dropped
  in the admin. Its content stays raw in object storage (`raw_payload_id`);
  the same file is never read twice for a country (`sha256`).
  """
  use Ecto.Schema

  @statuses ~w(new extracting extracted failed no_key ignored)
  def statuses, do: @statuses

  schema "budget_documents" do
    field :country_code, :string
    field :origin, :string
    field :url, :string
    field :filename, :string
    field :content_type, :string
    field :sha256, :string
    field :raw_payload_id, :integer
    field :status, :string, default: "new"
    field :error, :string
    timestamps(type: :utc_datetime)
  end
end
