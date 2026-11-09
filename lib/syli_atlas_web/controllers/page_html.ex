defmodule SyliAtlasWeb.PageHTML do
  use SyliAtlasWeb, :html

  embed_templates "page_html/*"

  def spark_path(values, from, to) do
    pts =
      values
      |> SyliAtlasWeb.Charts.rebase(from)
      |> Enum.with_index(2015)
      |> Enum.filter(fn {v, _} -> is_number(v) end)

    {lo, hi} = pts |> Enum.map(&elem(&1, 0)) |> Enum.min_max()
    to_xy = fn {v, yr} -> {4 + 292 * (yr - 2015) / 15, 54 - (v - lo) / max(hi - lo, 1) * 48} end
    past = for {v, yr} <- pts, yr <= 2025, do: to_xy.({v, yr})
    future = for {v, yr} <- pts, yr >= 2025, do: to_xy.({v, yr})
    dot = Enum.find_value(pts, fn {v, yr} -> yr == to && to_xy.({v, yr}) end)
    %{past: points(past), future: points(future), dot: dot}
  end

  defp points([]), do: ""

  defp points(list),
    do:
      "M" <>
        Enum.map_join(list, " L", fn {x, y} ->
          "#{Float.round(x * 1.0, 1)} #{Float.round(y * 1.0, 1)}"
        end)
end
