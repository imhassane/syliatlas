defmodule Mix.Tasks.Budgets.RefreshImf do
  @shortdoc "Updates priv/data/imf_fiscal_monitor.json from the IMF DataMapper API"
  @moduledoc """
  Fetches general government revenue and expenditure (% of GDP, IMF Fiscal
  Monitor) for the 54 countries, 2015–2030, and rewrites
  `priv/data/imf_fiscal_monitor.json` (`SyliAtlas.Budgets.Imf`).

      mix budgets.refresh_imf
  """
  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Application.ensure_all_started(:req)
    path = "priv/data/imf_fiscal_monitor.json"

    countries =
      "priv/data/areas.json"
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("areas")
      |> Enum.filter(&(&1["kind"] == "country"))
      |> Enum.map(& &1["code"])

    case SyliAtlas.Budgets.Imf.fetch(countries) do
      {:ok, doc} ->
        File.write!(path, Jason.encode_to_iodata!(doc, pretty: true))
        covered = Enum.count(doc["countries"], fn {_, e} -> e["revenue"] != %{} end)

        Mix.shell().info(
          "#{doc["source"]["label"]}: #{covered} of #{length(countries)} countries"
        )

      {:error, reason} ->
        Mix.raise("IMF DataMapper: #{inspect(reason)}")
    end
  end
end
