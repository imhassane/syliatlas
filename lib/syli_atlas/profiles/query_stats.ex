defmodule SyliAtlas.Profiles.QueryStats do
  @moduledoc """
  Keeps the last durations of each JSON function in ETS and reports
  p50, p95 and p99 against the 1.5 ms budget. Shown in the admin.
  """
  use GenServer

  @table __MODULE__
  @keep 1_000
  @budget_us 1_500

  def budget_us, do: @budget_us

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    :telemetry.attach(__MODULE__, [:syli_atlas, :json_fn, :stop], &__MODULE__.handle_event/4, nil)
    {:ok, nil}
  end

  def handle_event(_event, %{duration: native}, %{name: name, rows: rows}, _config) do
    us = System.convert_time_unit(native, :native, :microsecond)
    record(name, us, rows)
  end

  def record(name, us, rows) do
    {list, calls, _rows} =
      case :ets.lookup(@table, name) do
        [{^name, list, calls, _}] -> {list, calls, rows}
        [] -> {[], 0, rows}
      end

    :ets.insert(@table, {name, Enum.take([us | list], @keep), calls + 1, rows})
  rescue
    ArgumentError -> :ok
  end

  @doc "Percentiles per function, in microseconds."
  def summary do
    @table
    |> :ets.tab2list()
    |> Enum.map(fn {name, list, calls, rows} ->
      sorted = Enum.sort(list)

      %{
        name: name,
        calls: calls,
        rows: rows,
        p50: percentile(sorted, 0.50),
        p95: percentile(sorted, 0.95),
        p99: percentile(sorted, 0.99),
        max: List.last(sorted),
        status: status(percentile(sorted, 0.95), percentile(sorted, 0.99))
      }
    end)
    |> Enum.sort_by(&(-&1.p99))
  rescue
    ArgumentError -> []
  end

  def reset, do: :ets.delete_all_objects(@table)

  defp status(p95, p99) do
    cond do
      p99 <= @budget_us -> :ok
      p95 <= @budget_us -> :limit
      true -> :over
    end
  end

  defp percentile([], _), do: 0

  defp percentile(sorted, q),
    do: Enum.at(sorted, min(length(sorted) - 1, trunc(q * length(sorted))))
end
