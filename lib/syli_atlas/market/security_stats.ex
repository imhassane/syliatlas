defmodule SyliAtlas.Market.SecurityStats do
  @moduledoc """
  What Syli Atlas computes on a security from the sessions it recorded (no
  other source): performance since the first recorded close, set against the
  exchange's index over the same days; highest and lowest close; volume of
  the last session against the average of the previous ones; rank of the
  security in its exchange by value traded.

  Nothing is shown before there are enough sessions: a performance needs two
  closes, an average volume five previous sessions.
  """

  @min_avg_sessions 5
  @avg_window 20

  @doc "The minimum number of previous sessions for an average volume."
  def min_avg_sessions, do: @min_avg_sessions

  @doc """
  `sessions`: the security's sessions, oldest first, each
  `%{"date" => iso, "close" => number | string, "volume" => integer | nil}`.
  `index_history`: the exchange index, `[[iso, value], …]` oldest first.
  `rows`: the security rows of the exchange document; `row`: this security.
  """
  def compute(sessions, index_history, rows, row) do
    closes = for s <- sessions, c = num(s["close"]), is_number(c), do: {s["date"], c}

    %{
      "sessions" => length(closes),
      "first_date" => closes |> List.first() |> elem_or_nil(0),
      "performance" => performance(closes),
      "index_performance" => index_performance(closes, index_history),
      "high" => closes |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> nil end) |> only_if(closes),
      "low" => closes |> Enum.map(&elem(&1, 1)) |> Enum.min(fn -> nil end) |> only_if(closes),
      "volume_ratio" => volume_ratio(sessions),
      "rank" => rank(rows, row),
      "traded" => Enum.count(rows, &traded?/1)
    }
  end

  defp performance([{_, first} | _] = closes) when length(closes) >= 2 and first > 0 do
    {_, last} = List.last(closes)
    Float.round((last / first - 1) * 100, 2)
  end

  defp performance(_), do: nil

  # The index on the first and last day of the security's closes (or the
  # nearest index value on or before each day).
  defp index_performance(closes, history) when length(closes) >= 2 and is_list(history) do
    {first_day, _} = List.first(closes)
    {last_day, _} = List.last(closes)
    points = for [d, v] <- history, n = num(v), is_number(n), do: {d, n}

    with a when is_number(a) and a > 0 <- value_on(points, first_day),
         b when is_number(b) <- value_on(points, last_day),
         false <- first_day == last_day do
      Float.round((b / a - 1) * 100, 2)
    else
      _ -> nil
    end
  end

  defp index_performance(_, _), do: nil

  defp value_on(points, day) do
    points
    |> Enum.filter(fn {d, _} -> d <= day end)
    |> List.last()
    |> elem_or_nil(1)
  end

  # Last session's volume against the average of up to 20 sessions before it.
  defp volume_ratio(sessions) do
    volumes = for s <- sessions, is_integer(s["volume"]), do: s["volume"]

    case Enum.reverse(volumes) do
      [last | previous] when length(previous) >= @min_avg_sessions ->
        window = Enum.take(previous, @avg_window)
        avg = Enum.sum(window) / length(window)
        if avg > 0, do: Float.round(last / avg, 1)

      _ ->
        nil
    end
  end

  defp rank(rows, row) do
    if traded?(row) do
      rows
      |> Enum.filter(&traded?/1)
      |> Enum.sort_by(&(-(&1["value"] || 0)))
      |> Enum.find_index(&(&1["ticker"] == row["ticker"]))
      |> case do
        nil -> nil
        i -> i + 1
      end
    end
  end

  defp traded?(r), do: r["current"] == true and is_number(r["value"]) and r["value"] > 0

  defp only_if(value, closes) when length(closes) >= 2, do: value
  defp only_if(_value, _closes), do: nil

  defp elem_or_nil(nil, _i), do: nil
  defp elem_or_nil(t, i), do: elem(t, i)

  defp num(n) when is_number(n), do: n * 1.0

  defp num(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp num(_), do: nil
end
