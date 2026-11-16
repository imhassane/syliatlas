defmodule SyliAtlasWeb.AfricaTradeComponents do
  @moduledoc """
  Blocks shared by Africa's trade page and the product pages
  (SyliAtlasWeb.AfricaTradeController): the chart of exports and imports
  since 2000 with its table, share bars, the steps of a processing chain
  and the table of countries. All drawn on the server, readable without
  JavaScript; every chart has its figures as a table.
  """
  use Phoenix.Component
  use Gettext, backend: SyliAtlasWeb.Gettext

  import SyliAtlasWeb.UI, only: [flag: 1]
  alias SyliAtlasWeb.{Paths, TradeRankingController, TradeTopics, WorldBankComponents}

  def pct(v, locale), do: TradeRankingController.pct(v, locale)
  def usd(v, locale), do: WorldBankComponents.usd(v, locale)

  # History ------------------------------------------------------------------

  attr :id, :string, required: true
  attr :points, :list, required: true, doc: "[{year, exports, imports}]"
  attr :label, :string, required: true, doc: "what the chart shows, for screen readers"
  attr :locale, :string, required: true
  attr :imports, :boolean, default: true, doc: "draw the imports too"
  attr :first, :atom, default: :exports, values: [:exports, :imports]
  attr :source, :string, required: true

  @doc "Exports (and imports) since 2000, a line each, with the figures as a table."
  def history_chart(assigns) do
    series =
      [{:exports, 1}, {:imports, 2}]
      |> Enum.filter(fn {k, _} -> k == :exports or assigns.imports end)

    chart = chart(assigns.points, Enum.map(series, &elem(&1, 0)))
    assigns = assign(assigns, chart: chart, series: series)

    ~H"""
    <div class="stack gap-3" id={@id}>
      <ul class="chart-legend" aria-hidden="true">
        <li :for={{k, _} <- @series} class={"legend-#{k}"}>
          <span class="legend-swatch"></span>{series_label(k)}
        </li>
      </ul>
      <svg class="chart" viewBox="0 0 760 260" role="img" aria-label={@label}>
        <line :for={t <- @chart.ticks} class="grid-line" x1="64" x2="740" y1={t.y} y2={t.y}></line>
        <text :for={t <- @chart.ticks} x="56" y={t.y + 4} text-anchor="end">
          {tick(t.v, @locale)}
        </text>
        <text :for={{y, x} <- @chart.years} x={x} y="252" text-anchor="middle">{y}</text>
        <path
          :if={@first == :exports}
          d={@chart.areas[:exports]}
          style="fill: var(--accent-bg)"
        >
        </path>
        <path
          :for={{k, _} <- @series}
          class={["series", "series-#{k}"]}
          d={@chart.lines[k]}
        >
        </path>
      </svg>
      <details class="chart-data" id={@id <> "-data"}>
        <summary>{gettext("Chart data as a table")}</summary>
        <div class="table-box" role="region" aria-labelledby={@id <> "-caption"} tabindex="0">
          <table class="table">
            <caption id={@id <> "-caption"}>{@label}</caption>
            <thead>
              <tr>
                <th scope="col" class="l">{gettext("Year")}</th>
                <th :for={{k, _} <- @series} scope="col">{series_label(k)}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={{y, e, i} <- @points}>
                <th scope="row" class="l">{y}</th>
                <td>{usd(e, @locale)}</td>
                <td :if={@imports}>{usd(i, @locale)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </details>
      <p class="src">{@source}</p>
    </div>
    """
  end

  defp series_label(:exports), do: gettext("Exports")
  defp series_label(:imports), do: gettext("Imports")

  @doc false
  def chart(points, keys) do
    {x0, x1, y0, y1} = {64, 740, 230, 16}
    {first, _, _} = hd(points)
    {last, _, _} = List.last(points)
    value = fn {_, e, i}, k -> if k == :exports, do: e || 0, else: i || 0 end
    max = points |> Enum.flat_map(fn p -> Enum.map(keys, &value.(p, &1)) end) |> Enum.max()
    step = nice_step(max / 4)
    top = if max == 0, do: 1, else: step * trunc(Float.ceil(max / step))
    span = max(last - first, 1)
    x = fn year -> Float.round(x0 + (x1 - x0) * (year - first) / span, 1) end
    y = fn v -> Float.round(y0 - (y0 - y1) * v / top, 1) end

    lines =
      Map.new(keys, fn k ->
        d =
          points
          |> Enum.with_index()
          |> Enum.map_join(" ", fn {{yr, _, _} = p, i} ->
            "#{if i == 0, do: "M", else: "L"}#{x.(yr)} #{y.(value.(p, k))}"
          end)

        {k, d}
      end)

    %{
      lines: lines,
      areas:
        Map.new(lines, fn {k, d} -> {k, "#{d} L#{x.(last)} #{y0} L#{x.(first)} #{y0} Z"} end),
      ticks: for(i <- 0..trunc(top / step), do: %{v: i * step, y: y.(i * step)}),
      years:
        for(yr <- first..last, rem(yr - first, 4) == 0 or yr == last, do: {yr, x.(yr)})
        |> drop_crowded()
    }
  end

  defp nice_step(raw) when raw <= 0, do: 1

  defp nice_step(raw) do
    mag = :math.pow(10, :math.floor(:math.log10(raw)))

    cond do
      raw / mag <= 1 -> mag
      raw / mag <= 2 -> 2 * mag
      raw / mag <= 5 -> 5 * mag
      true -> 10 * mag
    end
  end

  # The last year label is dropped when it would overlap the one before.
  defp drop_crowded(years) do
    case Enum.reverse(years) do
      [{_, xl} = l, {_, xp} | rest] when xl - xp < 40 -> Enum.reverse([l | rest])
      _ -> years
    end
  end

  defp tick(v, _locale) when v == 0, do: "0"

  defp tick(v, locale) when v >= 1.0e9 do
    b = v / 1.0e9

    SyliAtlasWeb.Format.number(b, if(b == trunc(b), do: 0, else: 1), locale) <>
      " " <> SyliAtlasWeb.Format.billions(locale)
  end

  defp tick(v, locale), do: usd(v, locale)

  # Share bars ---------------------------------------------------------------

  attr :id, :string, required: true
  attr :items, :list, required: true, doc: "%{label, share, href (optional), mark (bool)}"
  attr :locale, :string, required: true
  attr :alt, :boolean, default: false, doc: "second colour"

  @doc "Labelled shares with a bar each, the largest as the scale."
  def share_bars(assigns) do
    max = assigns.items |> Enum.map(&(&1.share || 0)) |> Enum.max(fn -> 1 end)
    assigns = assign(assigns, max: if(max > 0, do: max, else: 1))

    ~H"""
    <ul class="share-list" id={@id}>
      <li :for={i <- @items} class={i[:mark] && "share-mark"}>
        <span class="share-label">
          <.any_flag :if={i[:flag]} code={i[:flag]} />
          <a :if={i[:href]} href={i[:href]}>{i.label}</a>
          <span :if={!i[:href]}>{i.label}</span>
        </span>
        <span class={["share-track", @alt && "share-track-alt"]} aria-hidden="true">
          <span style={"width: #{Float.round(100 * (i.share || 0) / @max, 1)}%"}></span>
        </span>
        <b class="num">{pct(i.share, @locale)}</b>
      </li>
    </ul>
    """
  end

  # Processing chain -----------------------------------------------------------

  attr :steps, :list, required: true
  attr :countries, :map, required: true
  attr :locale, :string, required: true

  @doc """
  Africa's share in world exports at each step of a product's processing,
  from the raw product to the finished one: where Africa stops.
  """
  def chain(assigns) do
    max = assigns.steps |> Enum.map(&(&1["world_share"] || 0)) |> Enum.max(fn -> 1 end)
    assigns = assign(assigns, max: max(max, 1))

    ~H"""
    <ol class="chain" id="chain-steps">
      <li :for={{s, i} <- Enum.with_index(@steps, 1)} class="chain-step">
        <span class="chain-n" aria-hidden="true">{i}</span>
        <span class="chain-bar" aria-hidden="true">
          <span style={"--w: #{Float.round(100 * (s["world_share"] || 0) / @max, 1)}%"}></span>
        </span>
        <b class="chain-share num">{pct(s["world_share"], @locale)}</b>
        <span class="chain-label">{TradeTopics.step_label(s["codes"])}</span>
        <span class="chain-value small muted">
          {gettext("%{value} exported by Africa", value: usd(s["value"], @locale))}
        </span>
        <span :if={s["exporters"] != []} class="chain-who small subtle">
          {Enum.map_join(
            Enum.take(s["exporters"], 2),
            ", ",
            &"#{SyliAtlasWeb.AfricaTradeController.country_name(@countries, &1["code"], @locale)} #{pct(&1["share"], @locale)}"
          )}
        </span>
      </li>
    </ol>
    """
  end

  @doc "The sentence that reads a chain: where Africa's share is highest and how it ends."
  def chain_sentence([_ | _] = steps, locale) do
    first = hd(steps)
    last = List.last(steps)
    top = Enum.max_by(steps, &(&1["world_share"] || 0))

    cond do
      top == first ->
        gettext(
          "Africa weighs most at the start of the chain: %{share} of world exports at the “%{step}” step, then %{last_share} at the “%{last}” step. Most of the processing is done elsewhere.",
          share: pct(first["world_share"], locale),
          step: label(first),
          last_share: pct(last["world_share"], locale),
          last: label(last)
        )

      true ->
        gettext(
          "Africa weighs most at one step of processing, “%{step}”: %{share} of world exports, against %{first_share} for “%{first}” and %{last_share} for “%{last}”.",
          share: pct(top["world_share"], locale),
          step: label(top),
          first_share: pct(first["world_share"], locale),
          first: label(first),
          last_share: pct(last["world_share"], locale),
          last: label(last)
        )
    end
  end

  def chain_sentence(_, _), do: nil

  defp label(step), do: TradeTopics.step_label(step["codes"])

  # Countries ------------------------------------------------------------------

  attr :code, :string, required: true

  @doc "A small flag, or an empty frame of the same size when there is none (rows stay aligned)."
  def any_flag(assigns) do
    ~H"""
    <.flag :if={SyliAtlasWeb.Flags.sprite_href(@code)} code={@code} size="sm" sprite />
    <span
      :if={!SyliAtlasWeb.Flags.sprite_href(@code)}
      class="flag flag-sm flag-none"
      aria-hidden="true"
    ></span>
    """
  end

  @doc "Flag, name and link to the country's trade tab (or the name alone outside Africa)."
  attr :code, :string, required: true
  attr :countries, :map, required: true
  attr :locale, :string, required: true

  def country(assigns) do
    assigns = assign(assigns, c: assigns.countries[assigns.code])

    ~H"""
    <span class="trade-country">
      <.any_flag code={@code} />
      <a :if={@c} href={Paths.country_tab(@locale, @c.slug, :trade)}>{@c.name}</a>
      <span :if={!@c}>{SyliAtlas.AfricaTrade.partner_name(@code, @locale)}</span>
    </span>
    """
  end
end
