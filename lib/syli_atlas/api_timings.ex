defmodule SyliAtlas.ApiTimings do
  @moduledoc """
  Server time of each public API route, measured on every request
  (`SyliAtlasWeb.Plugs.ApiTiming`), kept in memory for the current hour,
  then written once an hour as percentiles (`SyliAtlas.Workers.ApiTimingWorker`).

  Budget: 10 ms at the 99th percentile. It covers the time spent in the
  server only; the network to the visitor comes on top and depends on
  the country.
  """
  use GenServer
  import Ecto.Query
  alias SyliAtlas.Repo

  @table __MODULE__
  @keep 5_000
  @budget_us 10_000

  @routes ~w(areas area csv compare ranking)

  @doc "The public routes that are measured and shown, in page order."
  def routes, do: @routes

  @doc "The budget at the 99th percentile, in microseconds."
  def budget_us, do: @budget_us

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    {:ok, nil}
  end

  @doc "Records one request of `route` that took `us` microseconds."
  def record(route, us, now \\ DateTime.utc_now())

  def record(route, us, now) when route in @routes do
    key = {hour(now), route}

    list =
      case :ets.lookup(@table, key) do
        [{^key, list}] -> list
        [] -> []
      end

    :ets.insert(@table, {key, Enum.take([us | list], @keep)})
    :ok
  rescue
    ArgumentError -> :ok
  end

  def record(_route, _us, _now), do: :ok

  @doc """
  Writes the finished hours (before the current one) to the database and
  forgets them. Returns how many rows were written.
  """
  def flush(now \\ DateTime.utc_now()) do
    current = hour(now)

    rows =
      for {{hour, route} = key, list} <- :ets.tab2list(@table),
          DateTime.compare(hour, current) == :lt,
          list != [] do
        :ets.delete(@table, key)
        sorted = Enum.sort(list)

        %{
          hour: hour,
          route: route,
          count: length(sorted),
          p50_us: percentile(sorted, 0.50),
          p95_us: percentile(sorted, 0.95),
          p99_us: percentile(sorted, 0.99),
          max_us: List.last(sorted)
        }
      end

    if rows != [] do
      Repo.insert_all("api_timings", rows,
        on_conflict: {:replace, [:count, :p50_us, :p95_us, :p99_us, :max_us]},
        conflict_target: [:hour, :route]
      )
    end

    length(rows)
  rescue
    ArgumentError -> 0
  end

  @doc """
  The last 24 measured hours of each route, for the API page:
  `%{route => %{hours: [...], p50: us, p95: us, p99: us, last: hour}}`,
  percentiles over the whole day (the worst hour for p95 and p99).
  Routes without measures are left out.
  """
  def last_day(now \\ DateTime.utc_now()) do
    since = now |> hour() |> DateTime.add(-24, :hour)

    from(t in "api_timings",
      where: t.hour >= type(^since, :utc_datetime),
      order_by: [asc: t.hour],
      select: %{
        hour: type(t.hour, :utc_datetime),
        route: t.route,
        count: t.count,
        p50_us: t.p50_us,
        p95_us: t.p95_us,
        p99_us: t.p99_us
      }
    )
    |> Repo.all()
    |> Enum.group_by(& &1.route)
    |> Map.new(fn {route, hours} ->
      {route,
       %{
         hours: hours,
         p50: hours |> Enum.map(& &1.p50_us) |> median(),
         p95: hours |> Enum.map(& &1.p95_us) |> Enum.max(),
         p99: hours |> Enum.map(& &1.p99_us) |> Enum.max(),
         last: List.last(hours).hour |> to_datetime()
       }}
    end)
  end

  @doc "The start of the hour (UTC) of a time."
  def hour(%DateTime{} = dt),
    do: %{DateTime.truncate(dt, :second) | minute: 0, second: 0, microsecond: {0, 0}}

  @doc false
  def reset, do: :ets.delete_all_objects(@table)

  defp percentile(sorted, q),
    do: Enum.at(sorted, min(length(sorted) - 1, trunc(q * length(sorted))))

  defp median(list) do
    sorted = Enum.sort(list)
    Enum.at(sorted, div(length(sorted), 2))
  end

  defp to_datetime(%DateTime{} = dt), do: dt
  defp to_datetime(%NaiveDateTime{} = dt), do: DateTime.from_naive!(dt, "Etc/UTC")

  defp to_datetime(text) when is_binary(text) do
    case DateTime.from_iso8601(text) do
      {:ok, dt, _} -> dt
      _ -> text |> NaiveDateTime.from_iso8601!() |> to_datetime()
    end
  end
end
