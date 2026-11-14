defmodule SyliAtlasWeb.Charts do
  @moduledoc """
  Server-rendered SVG charts, so figures show without JavaScript, offline
  and for search engines.

  Each chart also carries its values, already formatted, in
  `data-chart-tips` (see `tips/2`): `assets/js/ui/chart_tips.js` reads them
  to show a tooltip on hover, touch and keyboard (a slider over the chart,
  arrows to move from year to year, Enter to make the year the end of the
  period). Without JavaScript the reader stays hidden and the table under
  the chart gives the same figures.
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
  attr :source, :string, default: nil, doc: "source line of the tooltip"

  attr :pick, :boolean,
    default: true,
    doc: "the tooltip offers to make the year the end of the period (?to=)"

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
    <div class="chart-figure" id={@id <> "-figure"}>
      <.chart_svg {assigns} id={@id} anchor={@id <> "-figure"} size={:wide} class="chart-wide" />
      <.chart_svg
        {assigns}
        id={@id <> "-narrow"}
        anchor={@id <> "-figure"}
        size={:narrow}
        class="chart-narrow"
      />
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
    g = geometry(assigns, Map.fetch!(@sizes, assigns.size))
    tips = tips(assigns, g)

    assigns =
      assign(assigns,
        g: g,
        tips: tips,
        tips_json: Jason.encode!(tips),
        start: Enum.at(tips.points, tips.start)
      )

    ~H"""
    <div class={["chart-box", @class]} data-chart-tips={@tips_json}>
      <svg
        id={@id}
        class="chart"
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
      <div
        :if={@start}
        class="chart-reader"
        role="slider"
        tabindex="0"
        hidden
        aria-label={gettext("Read the chart year by year: %{label}", label: @label)}
        aria-orientation="horizontal"
        aria-valuemin="0"
        aria-valuemax={length(@tips.points) - 1}
        aria-valuenow={@tips.start}
        aria-valuetext={@start.valuetext}
      >
      </div>
      <div :if={@start} class="chart-tip" hidden></div>
    </div>
    """
  end

  @doc """
  What the tooltip shows, one point per year with at least one value:
  where to draw (viewBox units), the values formatted for the locale, the
  year's status (published, estimate, projection), the change over one year
  of the first series, and what a screen reader says (`valuetext`).
  """
  def tips(assigns, g) do
    est = assigns.estimate_from
    pick? = Map.get(assigns, :pick, true)

    points =
      for year <- @first..@last,
          i = year - @first,
          rows = tip_rows(assigns, g, i),
          Enum.any?(rows, & &1.y) do
        {status, kind} =
          cond do
            year < est -> {gettext("Published"), "data"}
            year == est -> {gettext("Estimate"), "estimate"}
            true -> {gettext("Projection"), "projection"}
          end

        change =
          case assigns.series do
            [first | _] -> tip_change(first, i, assigns.indicator, assigns.locale)
            [] -> nil
          end

        %{
          year: year,
          x: Float.round(g.x.(year) * 1.0, 1),
          title: Integer.to_string(year),
          status: status,
          kind: kind,
          rows: rows,
          change: change,
          pick:
            if(pick? and year > assigns.from,
              do: gettext("Show %{year} in the figures", year: year)
            ),
          valuetext:
            gettext("%{year}, %{status}: %{values}",
              year: year,
              status: String.downcase(status),
              values: Enum.map_join(rows, "; ", &"#{&1.name} #{&1.text}")
            )
        }
      end

    start =
      Enum.find_index(points, &(&1.year == assigns.to)) || max(length(points) - 1, 0)

    %{
      w: g.w,
      h: g.h,
      top: g.top,
      bottom: g.bottom,
      from: assigns.from,
      anchor: Map.get(assigns, :anchor, assigns.id),
      source: Map.get(assigns, :source),
      keys: gettext("← →: change year · Enter: show it in the figures"),
      start: start,
      points: points
    }
  end

  defp tip_rows(assigns, g, i) do
    for s <- assigns.series do
      v = Enum.at(s.values, i)

      %{
        name: s.name,
        color: s.color,
        y: if(is_number(v), do: Float.round(g.y.(v) * 1.0, 1)),
        text: Format.value(v, assigns.indicator, assigns.locale)
      }
    end
  end

  # « Côte d'Ivoire : +10,6 % sur un an »: points for a rate, percent for a level.
  defp tip_change(_s, 0, _indicator, _locale), do: nil

  defp tip_change(s, i, indicator, locale) do
    v = Enum.at(s.values, i)
    prev = Enum.at(s.values, i - 1)
    rate? = indicator in SyliAtlas.Sources.Indicators.rate_keys()

    delta =
      cond do
        not (is_number(v) and is_number(prev)) -> nil
        rate? -> v - prev
        prev > 0 and v > 0 -> (v / prev - 1) * 100
        true -> nil
      end

    if delta do
      sign = if delta > 0, do: "+", else: ""
      unit = if rate?, do: "pt", else: "%"

      gettext("%{name}: %{change} over one year",
        name: s.name,
        change: sign <> Format.number(delta, 1, locale) <> "\u00A0" <> unit
      )
    end
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
