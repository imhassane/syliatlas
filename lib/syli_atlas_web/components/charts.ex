defmodule SyliAtlasWeb.Charts do
  @moduledoc """
  Server-rendered SVG charts, so figures show without JavaScript, offline
  and for search engines. `assets/js/charts.js` redraws the same chart in
  the browser when the period changes.
  """
  use Phoenix.Component
  use Gettext, backend: SyliAtlasWeb.Gettext
  alias SyliAtlasWeb.Format

  @first 2015
  @last 2030

  @doc "Values rebased to 100 in `from` (used for the real GDP index)."
  def rebase(values, from) do
    base = Enum.at(values, from - @first)

    Enum.map(values, fn
      v when is_number(v) and is_number(base) and base != 0 -> v / base * 100
      _ -> nil
    end)
  end

  attr :id, :string, required: true

  attr :series, :list,
    required: true,
    doc: "maps with :id, :name, :color, :values, optional :strong"

  attr :indicator, :string, required: true
  attr :from, :integer, required: true
  attr :to, :integer, required: true
  attr :estimate_from, :integer, default: 2025
  attr :locale, :string, required: true
  attr :label, :string, required: true

  @doc """
  A line chart drawn twice: a wide one with labels at the end of each line,
  and a narrow one for phones (text stays readable, no end labels: a legend
  goes under it). CSS shows one or the other.

  Under it, the same figures as a table, folded (`<details>`): the text
  alternative of a complex image (RGAA 1.9, 1.10) for screen readers and
  anyone who wants the exact values.
  """
  def line_chart(assigns) do
    ~H"""
    <div class="chart-figure">
      <.chart_svg {assigns} id={@id} size={:wide} class="chart chart-wide" />
      <.chart_svg {assigns} id={@id <> "-narrow"} size={:narrow} class="chart chart-narrow" />
      <.chart_table {assigns} />
    </div>
    """
  end

  defp chart_table(assigns) do
    assigns = assign(assigns, :years, Enum.with_index(@first..@last))

    ~H"""
    <details class="chart-data" id={@id <> "-data"}>
      <summary>{gettext("Chart data as a table")}</summary>
      <div class="table-box" role="region" aria-labelledby={@id <> "-data-caption"} tabindex="0">
        <table class="table">
          <caption id={@id <> "-data-caption"}>{@label}</caption>
          <thead>
            <tr>
              <th scope="col" class="l">{gettext("Year")}</th>
              <th :for={s <- @series} scope="col">{s.name}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={{year, i} <- @years}>
              <th scope="row" class="l">
                {year}
                <span :if={year >= @estimate_from} class="muted">
                  · {if year == @estimate_from,
                    do: gettext("estimate"),
                    else: gettext("projection")}
                </span>
              </th>
              <td :for={s <- @series} class="num">
                {Format.value(Enum.at(s.values, i), @indicator, @locale)}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </details>
    """
  end

  @sizes %{
    wide: %{w: 760, h: 300, ml: 52, mt: 18, mb: 30, end_width: 150, labels: true},
    narrow: %{w: 360, h: 230, ml: 34, mt: 14, mb: 24, end_width: 10, labels: false}
  }

  defp chart_svg(assigns) do
    assigns = assign(assigns, :g, geometry(assigns, Map.fetch!(@sizes, assigns.size)))

    ~H"""
    <svg
      id={@id}
      class={@class}
      viewBox={"0 0 #{@g.w} #{@g.h}"}
      role="img"
      aria-label={@label}
      data-chart
    >
      <rect
        class="proj"
        x={@g.x.(@estimate_from)}
        y={@g.top}
        width={@g.x.(@g.last) - @g.x.(@estimate_from)}
        height={@g.bottom - @g.top}
        rx="4"
      />
      <line
        :for={t <- @g.ticks}
        class="grid-line"
        x1={@g.left}
        x2={@g.right}
        y1={@g.y.(t)}
        y2={@g.y.(t)}
      />
      <text :for={t <- @g.ticks} x={@g.left - 8} y={@g.y.(t) + 4} text-anchor="end">
        {tick(t, @indicator, @locale)}
      </text>
      <text :for={yr <- [2015, 2020, 2025, 2030]} x={@g.x.(yr)} y={@g.h - 8} text-anchor="middle">
        {yr}
      </text>
      <line class="ref-line" x1={@g.x.(@from)} x2={@g.x.(@from)} y1={@g.top} y2={@g.bottom} />
      <line class="ref-line" x1={@g.x.(@to)} x2={@g.x.(@to)} y1={@g.top} y2={@g.bottom} />
      <g :for={s <- Enum.reverse(@series)} class="draw" data-series={s.id}>
        <path
          class="series"
          d={path(s.values, @g, 2015, @estimate_from)}
          style={"stroke: var(#{s.color}); stroke-width: #{if s[:strong], do: 3, else: 2}"}
        />
        <path
          class="series future"
          d={path(s.values, @g, @estimate_from, @g.last)}
          style={"stroke: var(#{s.color}); stroke-width: #{if s[:strong], do: 3, else: 2}"}
        />
      </g>
      <text
        :for={l <- @g.labels}
        :if={@g.show_labels}
        class="label"
        x={@g.right + 8}
        y={l.y + 4}
        style={"fill: var(#{l.color})"}
        data-series={l.id}
      >
        {l.text}
      </text>
    </svg>
    """
  end

  defp geometry(assigns, size) do
    values = assigns.series |> Enum.flat_map(& &1.values) |> Enum.filter(&is_number/1)

    floor_with =
      if assigns.indicator in ~w(real_gdp_growth inflation fiscal_balance_pct_gdp current_account_pct_gdp),
        do: [0],
        else: []

    {lo, hi} = Enum.min_max(values ++ floor_with, fn -> {0, 1} end)
    {lo, hi, step} = nice(lo, hi)
    right = size.w - size.end_width
    bottom = size.h - size.mb

    x = fn year -> size.ml + (right - size.ml) * (year - @first) / (@last - @first) end
    y = fn v -> bottom - (v - lo) / (hi - lo) * (bottom - size.mt) end

    labels =
      assigns.series
      |> Enum.flat_map(fn s ->
        case last_point(s.values) do
          nil ->
            []

          {_i, v} ->
            [
              %{
                id: s.id,
                color: s.color,
                y: y.(v),
                text: s.name <> " " <> Format.number(v, 1, assigns.locale)
              }
            ]
        end
      end)
      |> spread()

    %{
      w: size.w,
      h: size.h,
      left: size.ml,
      right: right,
      top: size.mt - 6,
      show_labels: size.labels,
      bottom: bottom,
      last: @last,
      x: x,
      y: y,
      labels: labels,
      ticks:
        Enum.to_list(Stream.iterate(lo, &(&1 + step)) |> Enum.take_while(&(&1 <= hi + step / 2)))
    }
  end

  defp nice(lo, hi) when lo == hi, do: nice(lo - 1, hi + 1)

  defp nice(lo, hi) do
    raw = (hi - lo) / 4
    mag = :math.pow(10, Float.floor(:math.log10(raw)))
    step = Enum.find([1, 2, 2.5, 5, 10], &(&1 * mag >= raw)) * mag
    {Float.floor(lo / step) * step, Float.ceil(hi / step) * step, step}
  end

  defp path(values, g, from_year, to_year) do
    values
    |> Enum.with_index(@first)
    |> Enum.filter(fn {v, yr} -> is_number(v) and yr >= from_year and yr <= to_year end)
    |> Enum.map_join(" ", fn {v, yr} -> "#{fmt(g.x.(yr))},#{fmt(g.y.(v))}" end)
    |> case do
      "" -> ""
      points -> "M" <> String.replace(points, " ", " L")
    end
  end

  defp last_point(values) do
    values
    |> Enum.with_index()
    |> Enum.filter(fn {v, _} -> is_number(v) end)
    |> List.last()
    |> case do
      nil -> nil
      {v, i} -> {i, v}
    end
  end

  defp spread(labels) do
    labels
    |> Enum.sort_by(& &1.y)
    |> Enum.reduce([], fn
      l, [prev | _] = acc when l.y - prev.y < 15 -> [%{l | y: prev.y + 15} | acc]
      l, acc -> [l | acc]
    end)
    |> Enum.reverse()
  end

  defp tick(v, "real_gdp_index", locale), do: Format.number(v, 0, locale)

  defp tick(v, ind, locale) do
    if ind in SyliAtlas.Sources.Indicators.rate_keys(),
      do: Format.number(v, 0, locale) <> " %",
      else: Format.number(v, 0, locale)
  end

  defp fmt(n), do: :erlang.float_to_binary(n * 1.0, decimals: 1)
end
