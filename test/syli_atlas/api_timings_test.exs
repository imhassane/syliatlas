defmodule SyliAtlas.ApiTimingsTest do
  use SyliAtlas.DataCase, async: false
  use Oban.Testing, repo: SyliAtlas.Repo, engine: Oban.Engines.Lite

  alias SyliAtlas.ApiTimings

  setup do
    ApiTimings.reset()
    :ok
  end

  test "finished hours are written as percentiles, the current one waits" do
    now = ~U[2026-11-11 19:20:00Z]

    for us <- 1..100, do: ApiTimings.record("area", us * 10, ~U[2026-11-11 18:30:00Z])
    ApiTimings.record("area", 500, now)
    ApiTimings.record("search", 500, ~U[2026-11-11 18:30:00Z])

    assert ApiTimings.flush(now) == 1

    assert %{"area" => day} = ApiTimings.last_day(now)
    assert [%{count: 100, p50_us: 510, p95_us: 960, p99_us: 1000}] = day.hours
    assert day.p99 == 1000
    assert day.last == ~U[2026-11-11 18:00:00Z]

    # The current hour is written at the next flush.
    assert ApiTimings.flush(~U[2026-11-11 20:01:00Z]) == 1
  end

  test "the hourly worker probes every public route and writes" do
    SyliAtlas.Fixtures.load_snapshot!()

    assert :ok = perform_job(SyliAtlas.Workers.ApiTimingWorker, %{})

    # The probe's measures are in the current hour: written an hour later.
    assert ApiTimings.last_day() == %{}
    later = DateTime.add(DateTime.utc_now(), 1, :hour)
    assert ApiTimings.flush(later) == 6

    assert later |> ApiTimings.last_day() |> Map.keys() |> Enum.sort() ==
             ~w(area areas compare csv indicators ranking)
  end

  test "probed routes all answer" do
    SyliAtlas.Fixtures.load_snapshot!()
    assert Enum.all?(SyliAtlas.Workers.ApiTimingWorker.probe(), &(&1 == 200))
  end
end
