defmodule SyliAtlasWeb.Spark do
  @moduledoc """
  Small line of a series (2015–2030) rebased to 100 in a reference year:
  the past as a solid path, estimates and projections dashed, a dot on the
  arrival year. `assets/js/ui/map.js` draws the same with the same maths.
  """

  @doc "%{past, future, dot: {x, y} | nil, base_x}"
  def paths(values, from, to, w \\ 260, h \\ 56, estimate_from \\ 2025)

  def paths(values, from, to, w, h, estimate_from) when is_list(values) do
    pts =
      values
      |> SyliAtlasWeb.Charts.rebase(from)
      |> Enum.with_index(2015)
      |> Enum.filter(fn {v, _} -> is_number(v) end)

    case pts do
      [] ->
        %{past: "", future: "", dot: nil, base_x: 0}

      _ ->
        {lo, hi} = pts |> Enum.map(&elem(&1, 0)) |> Enum.min_max()
        x = fn yr -> 4 + (w - 8) * (yr - 2015) / 15 end
        xy = fn {v, yr} -> {x.(yr), h - 4 - (v - lo) / max(hi - lo, 1) * (h - 8)} end

        %{
          past: path(for({v, yr} <- pts, yr <= estimate_from, do: xy.({v, yr}))),
          future: path(for({v, yr} <- pts, yr >= estimate_from, do: xy.({v, yr}))),
          dot: Enum.find_value(pts, fn {v, yr} -> yr == to && xy.({v, yr}) end),
          base_x: Float.round(x.(from) * 1.0, 1)
        }
    end
  end

  def paths(_values, _from, _to, _w, _h, _e), do: %{past: "", future: "", dot: nil, base_x: 0}

  defp path([]), do: ""

  defp path(list),
    do:
      "M" <>
        Enum.map_join(list, " L", fn {x, y} ->
          "#{Float.round(x * 1.0, 1)} #{Float.round(y * 1.0, 1)}"
        end)
end
