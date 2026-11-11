defmodule SyliAtlas.Workers.ApiTimingWorker do
  @moduledoc """
  Every hour: asks each public API route a few times (a probe, so that a
  route nobody called still has its measure), then writes the finished
  hours of `SyliAtlas.ApiTimings` to the database and forgets the rows
  older than 30 days.

  The probe runs inside the application (`Endpoint.call/2`), through the
  whole stack like a visitor's request, without the network.
  """
  use Oban.Worker, queue: :computations, max_attempts: 2, unique: [period: 600]

  import Ecto.Query

  @probes [
    "/api/v1/areas",
    "/api/v1/areas/CIV",
    "/api/v1/areas/NGA?from=2015&to=2030",
    "/api/v1/areas/CIV/csv",
    "/api/v1/compare?codes=CIV,GHA,SEN",
    "/api/v1/ranking",
    "/api/v1/ranking?indicator=inflation&mode=value",
    "/api/v1/indicators"
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    if Map.get(args, "probe", true), do: probe()
    SyliAtlas.ApiTimings.flush()

    cutoff = DateTime.utc_now() |> DateTime.add(-30, :day)

    SyliAtlas.Repo.delete_all(
      from t in "api_timings", where: t.hour < type(^cutoff, :utc_datetime)
    )

    :ok
  end

  @doc "Calls each probed route once, in process. Returns the statuses."
  def probe do
    endpoint = SyliAtlasWeb.Endpoint
    opts = endpoint.init([])

    for path <- @probes do
      Plug.Test.conn(:get, path)
      |> Map.put(:host, endpoint.host())
      |> endpoint.call(opts)
      |> Map.fetch!(:status)
    end
  end
end
