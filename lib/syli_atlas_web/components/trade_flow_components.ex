defmodule SyliAtlasWeb.TradeFlowComponents do
  @moduledoc """
  The flow chart of Africa's trade on the home page, read like a household
  budget: on the left what Africa sells (its income), at the centre the
  continent, on the right what it buys (its spending). When purchases
  exceed sales, a dashed « trade deficit » ribbon fills the gap on the
  left; when sales exceed purchases, a « trade surplus » ribbon leaves on
  the right.

  Families of products come from `SyliAtlas.AfricaTrade` (CEPII, BACI,
  grouped from HS chapters by `scripts/build_africa_trade.py`). Drawn on the
  server as SVG: wide screens get the left-to-right chart, phones a
  top-to-bottom one with its two legends. The figures are also a table.
  """
  use Phoenix.Component
  use Gettext, backend: SyliAtlasWeb.Gettext

  alias SyliAtlasWeb.{AfricaTradeComponents, TradeTopics}

  # The site's map of Africa as one dark silhouette (small islands left out:
  # at this size they are specks).
  @map_file Path.join([__DIR__, "..", "..", "..", "priv", "data", "africa_map.json"])
            |> Path.expand()
  @external_resource @map_file
  @map (
         doc = @map_file |> File.read!() |> Jason.decode!()

         d =
           doc["areas"]
           |> Enum.reject(fn {code, _} -> code in ~w(CPV SYC MUS COM STP) end)
           |> Enum.flat_map(fn {_, a} -> String.split(a["d"], ~r/(?=M)/, trim: true) end)
           |> Enum.filter(&(String.length(&1) > 120))
           |> Enum.join()

         %{d: d, width: doc["width"], height: doc["height"]}
       )

  @export_order ~w(energy minerals precious farm machines other)
  @import_order ~w(machines energy food chemicals vehicles metals other)
  @export_colors %{
    "energy" => "#4b3bff",
    "minerals" => "#8a3ffc",
    "precious" => "#b97d0c",
    "farm" => "#00875a",
    "machines" => "#3b6cff",
    "other" => "#7c8299"
  }
  @import_color "#f25a28"
  @gap_color "#c2410c"

  def export_label("energy"), do: gettext("Oil, gas and coal")
  def export_label("minerals"), do: gettext("Ores and metals")
  def export_label("precious"), do: gettext("Gold, diamonds and platinum")
  def export_label("farm"), do: gettext("Farm products")
  def export_label("machines"), do: gettext("Machines and vehicles")
  def export_label(_), do: gettext("Other products")

  def import_label("machines"), do: gettext("Machines and electronics")
  def import_label("energy"), do: gettext("Fuels and energy")
  def import_label("food"), do: gettext("Food")
  def import_label("chemicals"), do: gettext("Chemicals and medicines")
  def import_label("vehicles"), do: gettext("Vehicles")
  def import_label("metals"), do: gettext("Metals")
  def import_label(_), do: gettext("Other products")

  @doc """
  The flows of a year: `%{left: [node], right: [node], exports, imports,
  total}`, each node `%{key, label, value, color, gap}`; nil without data.
  """
  def flows(%{"families" => %{"exports" => ex, "imports" => im}} = a) do
    left =
      for k <- @export_order,
          v = ex[k],
          v && v > 0,
          do: %{
            key: k,
            label: export_label(k),
            value: v,
            color: @export_colors[k],
            gap: false,
            side: :left
          }

    right =
      for k <- @import_order,
          v = im[k],
          v && v > 0,
          do: %{
            key: k,
            label: import_label(k),
            value: v,
            color: @import_color,
            gap: false,
            side: :right
          }

    gap = a["imports"] - a["exports"]

    {left, right} =
      cond do
        gap > 0 ->
          {left ++
             [
               %{
                 key: "gap",
                 label: gettext("Trade deficit"),
                 value: gap,
                 color: @gap_color,
                 gap: true,
                 side: :left
               }
             ], right}

        gap < 0 ->
          {left,
           right ++
             [
               %{
                 key: "gap",
                 label: gettext("Trade surplus"),
                 value: -gap,
                 color: @gap_color,
                 gap: true,
                 side: :right
               }
             ]}

        true ->
          {left, right}
      end

    %{
      left: left,
      right: right,
      exports: a["exports"],
      imports: a["imports"],
      gap: gap,
      total: max(a["exports"], a["imports"])
    }
  end

  def flows(_), do: nil

  # Geometry ------------------------------------------------------------------

  @doc false
  def wide(f) do
    {w, h, lx, rx, nw, gap, top} = {1152, 470, 240, 900, 14, 10, 10}
    n = max(length(f.left), length(f.right))
    k = (h - 2 * top - gap * (n - 1)) / f.total
    cx = w / 2
    my = h / 2
    k2 = 56 / f.total
    cy = my - 12 - f.total * k2 / 2

    left = stack(f.left, top, k, gap, cy, k2)
    right = stack(f.right, top, k, gap, cy, k2)

    %{
      w: w,
      h: h,
      map: map(cx, my, 150),
      label_y: r(my + 75 + 18),
      cx: cx,
      left:
        for n <- left do
          mx = r((lx + nw + cx - 6) / 2)

          Map.merge(n, %{
            path: ribbon(lx + nw, n.y, n.h, cx - 6, n.cy, n.h2, mx),
            x: lx,
            label_x: lx - 12,
            anchor: "end"
          })
        end,
      right:
        for n <- right do
          mx = r((cx + 6 + rx) / 2)

          Map.merge(n, %{
            path: ribbon(cx + 6, n.cy, n.h2, rx, n.y, n.h, mx),
            x: rx,
            label_x: rx + nw + 12,
            anchor: "start"
          })
        end,
      nw: nw
    }
  end

  @doc false
  def narrow(f) do
    {w, h, barh, gap} = {350, 430, 16, 3}
    n = max(length(f.left), length(f.right))
    k = (w - gap * (n - 1)) / f.total
    cx = w / 2
    my = h / 2
    waist = 26
    wk = waist / f.total

    row = fn nodes, y_bar, y_waist, down? ->
      {out, _, _} =
        Enum.reduce(nodes, {[], 0.0, cx - waist / 2}, fn node, {acc, x, wx} ->
          bw = node.value * k
          ww = node.value * wk
          y_bar_edge = if down?, do: y_bar + barh, else: y_bar
          m = r((y_bar_edge + y_waist) / 2)

          path =
            "M#{r(x)} #{y_bar_edge} C#{r(x)} #{m} #{r(wx)} #{m} #{r(wx)} #{y_waist} " <>
              "L#{r(wx + ww)} #{y_waist} C#{r(wx + ww)} #{m} #{r(x + bw)} #{m} #{r(x + bw)} #{y_bar_edge} Z"

          {[Map.merge(node, %{x: r(x), bw: r(bw), y: y_bar, path: path}) | acc], x + bw + gap,
           wx + ww}
        end)

      Enum.reverse(out)
    end

    %{
      w: w,
      h: h,
      barh: barh,
      top: row.(f.left, 0, my - 4, true),
      bottom: row.(f.right, h - barh, my + 18, false),
      map: map(cx, my, 96)
    }
  end

  defp stack(nodes, top, k, gap, cy, k2) do
    {out, _, _} =
      Enum.reduce(nodes, {[], top * 1.0, cy}, fn node, {acc, y, cyy} ->
        nh = node.value * k
        nh2 = node.value * k2

        {[Map.merge(node, %{y: r(y), h: r(max(nh, 2)), cy: r(cyy), h2: r(nh2)}) | acc],
         y + nh + gap, cyy + nh2}
      end)

    Enum.reverse(out)
  end

  defp ribbon(x1, y1, h1, x2, y2, h2, mx),
    do:
      "M#{r(x1)} #{r(y1)} C#{mx} #{r(y1)} #{mx} #{r(y2)} #{r(x2)} #{r(y2)} " <>
        "L#{r(x2)} #{r(y2 + h2)} C#{mx} #{r(y2 + h2)} #{mx} #{r(y1 + h1)} #{r(x1)} #{r(y1 + h1)} Z"

  defp map(cx, cy, size) do
    k = size / @map.height
    width = @map.width * k

    %{
      d: @map.d,
      transform:
        "translate(#{r(cx - width / 2)} #{r(cy - size / 2)}) scale(#{Float.round(k, 4)})",
      stroke: Float.round(1.4 / k, 2)
    }
  end

  defp r(v), do: Float.round(v * 1.0, 1)

  # Component -----------------------------------------------------------------

  attr :africa, :map, required: true, doc: "SyliAtlas.AfricaTrade.africa()"
  attr :year, :integer, required: true
  attr :version, :string, required: true
  attr :locale, :string, required: true

  @doc "The home page's section: the sentence, the chart (two drawings), the table, the links."
  def home_flows(assigns) do
    f = flows(assigns.africa)
    assigns = assign(assigns, f: f, wide: f && wide(f), narrow: f && narrow(f))

    ~H"""
    <section :if={@f} class="section" id="commerce-afrique" aria-labelledby="flows-title">
      <div class="wrap stack gap-6">
        <div class="flows-head">
          <div class="stack gap-2 flows-intro">
            <p class="eyebrow">{gettext("Africa's trade · %{year}", year: @year)}</p>
            <h2 class="h1" id="flows-title">
              {if @f.gap > 0,
                do: gettext("What Africa sells pays for almost all it buys"),
                else: gettext("What Africa sells pays for all it buys")}
            </h2>
            <p class="lead muted" id="flows-answer">{sentence(@f, @year, @locale)}</p>
          </div>
          <a class="btn btn-primary flows-cta" href={TradeTopics.africa_path(@locale)} id="flows-link">
            {gettext("See Africa's trade")} →
          </a>
        </div>

        <div class="card pad flows-card" id="flows">
          <div class="flows-wide" id="flows-wide">
            <p class="flows-sides" aria-hidden="true">
              <span>{gettext("What it sells · %{value}", value: usd(@f.exports, @locale))}</span>
              <span>{gettext("What it buys · %{value}", value: usd(@f.imports, @locale))}</span>
            </p>
            <svg
              class="flows-svg"
              viewBox={"0 0 #{@wide.w} #{@wide.h}"}
              role="img"
              aria-label={label(@f, @year, @locale)}
            >
              <path
                :for={n <- @wide.left}
                d={n.path}
                class={["flow-ribbon", n.gap && "flow-gap"]}
                style={"--c: #{n.color}"}
              >
                <title>{n.label} : {usd(n.value, @locale)}</title>
              </path>
              <path
                :for={n <- @wide.right}
                d={n.path}
                class={["flow-ribbon flow-out", n.gap && "flow-gap"]}
                style={"--c: #{n.color}"}
              >
                <title>{n.label} : {usd(n.value, @locale)}</title>
              </path>
              <rect
                :for={n <- @wide.left ++ @wide.right}
                x={n.x}
                y={n.y}
                width={@wide.nw}
                height={n.h}
                rx="3"
                style={"fill: #{n.color}"}
              />
              <g class="flows-map" transform={@wide.map.transform} stroke-width={@wide.map.stroke}>
                <path d={@wide.map.d} />
              </g>
              <text x={@wide.cx} y={@wide.label_y} text-anchor="middle" class="flows-center">
                {gettext("54 countries")}
              </text>
              <g :for={n <- @wide.left ++ @wide.right} class="flows-label">
                <text x={n.label_x} y={n.y + n.h / 2 - 2} text-anchor={n.anchor} class="flows-name">
                  {n.label}
                </text>
                <text x={n.label_x} y={n.y + n.h / 2 + 15} text-anchor={n.anchor} class="flows-value">
                  {usd(n.value, @locale)}{share(n, @f, @locale)}
                </text>
              </g>
            </svg>
          </div>

          <div class="flows-narrow" id="flows-narrow">
            <p class="flows-side">
              {gettext("What it sells · %{value}", value: usd(@f.exports, @locale))}
            </p>
            <.legend nodes={@f.left} f={@f} locale={@locale} side={:left} />
            <svg
              class="flows-svg"
              viewBox={"0 0 #{@narrow.w} #{@narrow.h}"}
              role="img"
              aria-label={label(@f, @year, @locale)}
            >
              <path
                :for={n <- @narrow.top ++ @narrow.bottom}
                d={n.path}
                class={["flow-ribbon", n.side == :right && "flow-out", n.gap && "flow-gap"]}
                style={"--c: #{n.color}"}
              />
              <rect
                :for={n <- @narrow.top ++ @narrow.bottom}
                x={n.x}
                y={n.y}
                width={n.bw}
                height={@narrow.barh}
                rx="3"
                style={"fill: #{n.color}"}
                class={n.gap && "flow-gap-node"}
              />
              <g class="flows-map" transform={@narrow.map.transform} stroke-width={@narrow.map.stroke}>
                <path d={@narrow.map.d} />
              </g>
            </svg>
            <p class="flows-side">
              {gettext("What it buys · %{value}", value: usd(@f.imports, @locale))}
            </p>
            <.legend nodes={@f.right} f={@f} locale={@locale} side={:right} />
          </div>

          <details class="chart-data" id="flows-data">
            <summary>{gettext("Chart data as a table")}</summary>
            <div class="table-box" role="region" aria-labelledby="flows-caption" tabindex="0">
              <table class="table">
                <caption id="flows-caption">{label(@f, @year, @locale)}</caption>
                <thead>
                  <tr>
                    <th scope="col" class="l">{gettext("Family of products")}</th>
                    <th scope="col" class="l">{gettext("Flow")}</th>
                    <th scope="col">{gettext("Value")}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={n <- @f.left}>
                    <th scope="row" class="l">{n.label}</th>
                    <td class="l">{if n.gap, do: "—", else: gettext("Exports")}</td>
                    <td>{usd(n.value, @locale)}</td>
                  </tr>
                  <tr :for={n <- @f.right}>
                    <th scope="row" class="l">{n.label}</th>
                    <td class="l">{if n.gap, do: "—", else: gettext("Imports")}</td>
                    <td>{usd(n.value, @locale)}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </details>
          <p class="src">
            {gettext("Source: CEPII, BACI (version %{version}), Licence Ouverte Etalab 2.0",
              version: @version
            )} · {gettext("families of products: Syli Atlas grouping of HS chapters")}
          </p>
        </div>

        <div class="chips" id="flows-products">
          <a
            :for={id <- ~w(crude-oil gold wheat)}
            class="chip"
            href={TradeTopics.product_path(@locale, id)}
          >
            {TradeTopics.product_title(id)}
          </a>
          <a class="chip" href={TradeTopics.products_path(@locale)}>{gettext("All products")}</a>
        </div>
      </div>
    </section>
    """
  end

  attr :nodes, :list, required: true
  attr :f, :map, required: true
  attr :locale, :string, required: true
  attr :side, :atom, required: true

  defp legend(assigns) do
    ~H"""
    <ul class="flows-legend">
      <li :for={n <- @nodes} class={n.gap && "is-gap"}>
        <span class="flows-dot" style={"background: #{n.color}"} aria-hidden="true"></span>
        <span class="flows-legend-name">{n.label}</span>
        <b class="num">{usd(n.value, @locale)}</b>
        <span class="num subtle flows-legend-share">{if n.gap, do: "", else: pct(n, @f, @locale)}</span>
      </li>
    </ul>
    """
  end

  defp usd(v, locale), do: AfricaTradeComponents.usd(v, locale)

  defp base(%{side: :left}, f), do: f.exports
  defp base(_n, f), do: f.imports

  defp pct(n, f, locale) do
    SyliAtlasWeb.Format.number(100 * n.value / base(n, f), 0, locale) <> " %"
  end

  defp share(%{gap: true}, _f, _locale), do: ""
  defp share(n, f, locale), do: " · " <> pct(n, f, locale)

  defp label(f, year, locale) do
    gettext(
      "Africa's trade in %{year}: %{exports} of exports and %{imports} of imports, by family of products",
      year: year,
      exports: usd(f.exports, locale),
      imports: usd(f.imports, locale)
    )
  end

  @doc false
  def sentence(f, year, locale) do
    [a, b | _] = Enum.reject(f.left, & &1.gap)
    [c, d | _] = Enum.reject(f.right, &(&1.gap or &1.key == "other"))

    gettext(
      "In %{year}, the 54 countries sold %{exports} of goods and bought %{imports}. Sales come first from “%{a}” (%{sa}) and “%{b}” (%{sb}); purchases from “%{c}” (%{sc}) and “%{d}” (%{sd}).",
      year: year,
      exports: usd(f.exports, locale),
      imports: usd(f.imports, locale),
      a: a.label,
      sa: pct(a, f, locale),
      b: b.label,
      sb: pct(b, f, locale),
      c: c.label,
      sc: pct(c, f, locale),
      d: d.label,
      sd: pct(d, f, locale)
    ) <>
      " " <>
      cond do
        f.gap > 0 -> gettext("It lacks %{gap}.", gap: usd(f.gap, locale))
        f.gap < 0 -> gettext("%{gap} are left over.", gap: usd(-f.gap, locale))
        true -> ""
      end
  end
end
