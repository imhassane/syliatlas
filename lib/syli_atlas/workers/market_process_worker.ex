defmodule SyliAtlas.Workers.MarketProcessWorker do
  @moduledoc "Parses, checks and consolidates one stored payload, then asks for a publication."
  use Oban.Worker, queue: :market, max_attempts: 3, unique: [keys: [:payload_id], period: 600]

  alias SyliAtlas.Market.Pipeline

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payload_id" => id}}) do
    case Pipeline.process(id) do
      {:ok, _summary} ->
        SyliAtlas.Workers.MarketPublishWorker.new(%{}, schedule_in: 30) |> Oban.insert()
        :ok

      {:error, reason} ->
        {:cancel, inspect(reason)}
    end
  end
end
