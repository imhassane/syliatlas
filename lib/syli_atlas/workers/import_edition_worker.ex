defmodule SyliAtlas.Workers.ImportEditionWorker do
  @moduledoc "Downloads a new IMF edition and brings it online."
  use Oban.Worker, queue: :imports, max_attempts: 5, unique: [keys: [:label], period: 3600]

  alias SyliAtlas.Imports
  alias SyliAtlas.Imports.ImfClient

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"label" => label} = args}) do
    with {:ok, payload} <- ImfClient.fetch_values() do
      case Imports.import_payload(label, payload, force: Map.get(args, "force", false)) do
        {:ok, :published, edition} ->
          SyliAtlas.Workers.AfterPublishWorker.new(%{edition_id: edition.id}) |> Oban.insert()

        {:ok, :already_published, _edition} ->
          :ok

        {:error, reasons} ->
          {:cancel, Enum.join(List.wrap(reasons), ", ")}
      end
    end
  end
end
