defmodule SyliAtlas.Workers.CheckSourcesWorker do
  @moduledoc """
  Runs every morning. Asks the IMF which edition is current and enqueues
  an import when it differs from the one online.
  """
  use Oban.Worker, queue: :imports, max_attempts: 5, unique: [period: 3600]

  alias SyliAtlas.Sources
  alias SyliAtlas.Imports.{ImfClient, ImfParser}
  alias SyliAtlas.Workers.ImportEditionWorker

  @impl Oban.Worker
  def perform(_job) do
    source = Sources.get_source!("imf_weo")
    Sources.touch_source!(source)

    with {:ok, label} <- ImfClient.fetch_label(),
         {:ok, code} <- ImfParser.edition_code(label) do
      online = Sources.published_edition("imf_weo")

      if online && online.code == code do
        {:ok, :up_to_date}
      else
        %{label: label} |> ImportEditionWorker.new() |> Oban.insert()
      end
    end
  end
end
