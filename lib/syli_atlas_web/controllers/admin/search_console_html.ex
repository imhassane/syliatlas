defmodule SyliAtlasWeb.Admin.SearchConsoleHTML do
  use SyliAtlasWeb, :html

  import SyliAtlasWeb.AdminComponents, only: [admin_shell: 1]

  embed_templates "search_console_html/*"

  def n(nil), do: "—"
  def n(v) when is_integer(v), do: SyliAtlasWeb.Format.number(v, 0, "fr")
  def n(v) when is_float(v), do: SyliAtlasWeb.Format.number(v, 1, "fr")

  def ctr(_clicks, 0), do: "—"

  def ctr(clicks, impressions),
    do: SyliAtlasWeb.Format.number(clicks / impressions * 100, 1, "fr") <> " %"

  def day(%Date{} = d), do: Calendar.strftime(d, "%d/%m")
  def day(_), do: ""

  @months ~w(janv. févr. mars avr. mai juin juil. août sept. oct. nov. déc.)
  def long_day(%Date{} = d), do: "#{d.day} #{Enum.at(@months, d.month - 1)}"
  def long_day(_), do: ""

  def import_label(:waiting), do: "en attente"
  def import_label(:running), do: "en cours"
  def import_label(:done), do: "réussi"
  def import_label(:retrying), do: "échec, nouvel essai prévu"
  def import_label(:failed), do: "échec"

  def lang_name("pt"), do: "Portugais"
  def lang_name("es"), do: "Espagnol"
  def lang_name("ar"), do: "Arabe"
  def lang_name("zh"), do: "Chinois"
  def lang_name("hi"), do: "Hindi"
  def lang_name("fr"), do: "Français"
  def lang_name("en"), do: "Anglais"
  def lang_name(l), do: l

  def device_name("DESKTOP"), do: "Ordinateur"
  def device_name("MOBILE"), do: "Téléphone"
  def device_name("TABLET"), do: "Tablette"
  def device_name(d), do: d

  @doc "The results page of an average position: « 1 » for 1–10…"
  def results_page(nil), do: nil
  def results_page(pos), do: max(1, ceil(pos / 10))

  @doc "A position as a coloured pill: page 1, page 2, further."
  def position_pill(assigns) do
    ~H"""
    <span class={[
      "pill no-dot",
      cond do
        is_nil(@pos) -> "pill-neutral"
        @pos <= 10 -> "pill-info"
        @pos <= 20 -> "pill-warn"
        true -> "pill-neutral"
      end
    ]}>
      {n(@pos)}<span :if={@pos}> · {pos_label(@pos)}</span>
    </span>
    """
  end

  defp pos_label(p) when p <= 10, do: "page 1"
  defp pos_label(p) when p <= 20, do: "page 2"
  defp pos_label(p) when p <= 30, do: "page 3"
  defp pos_label(_), do: "loin"

  def band_label(:top3), do: "Top 3"
  def band_label(:page1), do: "Première page (4–10)"
  def band_label(:page2), do: "Deuxième page (11–20)"
  def band_label(:further), do: "Plus loin"

  def band_color(:top3), do: "#00704a"
  def band_color(:page1), do: "#4b3bff"
  def band_color(:page2), do: "#9fb0ff"
  def band_color(:further), do: "var(--border-strong)"

  def tab_label("requetes"), do: "Requêtes"
  def tab_label("pages"), do: "Pages"
  def tab_label("langues"), do: "Langues"
  def tab_label("appareils"), do: "Appareils"
  def tab_label("pays"), do: "Pays"

  def key_label("requetes"), do: "Ce que les gens ont tapé"
  def key_label("pages"), do: "Page"
  def key_label("langues"), do: "Langue"
  def key_label("appareils"), do: "Appareil"
  def key_label("pays"), do: "Pays du lecteur"

  def key_text("langues", k), do: lang_name(k)
  def key_text("appareils", k), do: device_name(k)
  def key_text("pays", k), do: String.upcase(k)
  def key_text("pages", k), do: URI.parse(k).path || k
  def key_text(_, k), do: k

  @doc "Path part of a page address."
  def path(nil), do: nil
  def path(url), do: URI.parse(url).path || url

  # ---------------------------------------------------------------------------
  # Chart: bars for impressions (left scale), a line for clicks (right
  # scale); or a line for the average position (1 at the top).

  @w 1000
  @h 300
  @left 64
  @right 64
  @top 24
  @bottom 56

  def chart(assigns) do
    rows = assigns.rows
    count = max(length(rows), 1)
    slot = (@w - @left - @right) / count
    bar = min(slot * 0.62, 120)
    plot_h = @h - @top - @bottom
    base = @top + plot_h

    max_imp = rows |> Enum.map(& &1.impressions) |> Enum.max(fn -> 0 end) |> nice()
    max_clk = rows |> Enum.map(& &1.clicks) |> Enum.max(fn -> 0 end) |> nice()
    max_pos = rows |> Enum.map(&(&1.position || 0)) |> Enum.max(fn -> 0 end) |> nice()

    every = max(1, div(count + 9, 10))

    points =
      for {r, i} <- Enum.with_index(rows) do
        cx = @left + slot * i + slot / 2
        imp_h = if max_imp > 0, do: r.impressions / max_imp * plot_h, else: 0
        clk_y = base - if(max_clk > 0, do: r.clicks / max_clk * plot_h, else: 0)

        pos_y =
          if r.position && max_pos > 0,
            do: @top + (r.position - 1) / max(max_pos - 1, 1) * plot_h

        %{
          r: r,
          cx: cx,
          x: cx - bar / 2,
          bar: bar,
          imp_h: max(imp_h, if(r.impressions > 0, do: 1.5, else: 0)),
          clk_y: clk_y,
          pos_y: pos_y,
          label?: rem(count - 1 - i, every) == 0
        }
      end

    assigns =
      assign(assigns,
        w: @w,
        h: @h,
        left: @left,
        right: @w - @right,
        top: @top,
        base: base,
        mid: @top + plot_h / 2,
        points: points,
        max_imp: max_imp,
        max_clk: max_clk,
        max_pos: max_pos,
        clicks_line: Enum.map_join(points, " ", &"#{fmt(&1.cx)},#{fmt(&1.clk_y)}"),
        pos_line:
          points
          |> Enum.filter(& &1.pos_y)
          |> Enum.map_join(" ", &"#{fmt(&1.cx)},#{fmt(&1.pos_y)}")
      )

    ~H"""
    <svg
      viewBox={"0 0 #{@w} #{@h}"}
      width="100%"
      height="300"
      role="img"
      aria-label={@aria}
      id="gsc-chart-svg"
      class="gsc-chart"
    >
      <g stroke="var(--border)" stroke-width="1">
        <line x1={@left} y1={@top} x2={@right} y2={@top} stroke-dasharray="3 5" />
        <line x1={@left} y1={@mid} x2={@right} y2={@mid} stroke-dasharray="3 5" />
        <line x1={@left} y1={@base} x2={@right} y2={@base} />
      </g>
      <%= if @measure == "rang" do %>
        <g font-family="JetBrains Mono" font-size="12" fill="var(--ink-subtle)" text-anchor="end">
          <text x={@left - 10} y={@top + 4}>1</text>
          <text x={@left - 10} y={@base + 4}>{n(@max_pos)}</text>
        </g>
        <polyline points={@pos_line} fill="none" stroke="#4b3bff" stroke-width="2.5" />
        <g fill="#4b3bff" stroke="var(--card)" stroke-width="2">
          <circle :for={p <- @points} :if={p.pos_y} cx={fmt(p.cx)} cy={fmt(p.pos_y)} r="5">
            <title>{long_day(p.r.date)} : rang {n(p.r.position)}</title>
          </circle>
        </g>
      <% else %>
        <g font-family="JetBrains Mono" font-size="12" fill="var(--ink-subtle)" text-anchor="end">
          <text x={@left - 10} y={@top + 4}>{n(@max_imp)}</text>
          <text x={@left - 10} y={@mid + 4}>{n(div(@max_imp, 2))}</text>
          <text x={@left - 10} y={@base + 4}>0</text>
        </g>
        <g font-family="JetBrains Mono" font-size="12" fill="var(--ink-subtle)" text-anchor="start">
          <text x={@right + 10} y={@top + 4}>{n(@max_clk)}</text>
          <text x={@right + 10} y={@base + 4}>0</text>
        </g>
        <rect
          :for={p <- @points}
          x={fmt(p.x)}
          y={fmt(@base - p.imp_h)}
          width={fmt(p.bar)}
          height={fmt(p.imp_h)}
          rx="3"
          fill="#4b3bff"
        >
          <title>
            {if(p.r.week, do: "Semaine du ", else: "")}{long_day(p.r.date)} : {n(p.r.impressions)} apparitions, {n(
              p.r.clicks
            )} visites, rang {n(p.r.position)}
          </title>
        </rect>
        <polyline points={@clicks_line} fill="none" stroke="#ff6b3d" stroke-width="2.5" />
        <g fill="#ff6b3d" stroke="var(--card)" stroke-width="2">
          <circle :for={p <- @points} cx={fmt(p.cx)} cy={fmt(p.clk_y)} r="4.5" />
        </g>
      <% end %>
      <g font-family="Inter Tight" font-size="12" fill="var(--ink-muted)" text-anchor="middle">
        <text :for={p <- @points} :if={p.label?} x={fmt(p.cx)} y={@h - 22}>{long_day(p.r.date)}</text>
      </g>
    </svg>
    """
  end

  defp fmt(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 1)
  defp fmt(v), do: to_string(v)

  # A round top for the scale: 1, 2, 5 × 10^n.
  defp nice(0), do: 0

  defp nice(v) do
    mag = :math.pow(10, floor(:math.log10(v)))

    step =
      Enum.find([1, 2, 5, 10], fn s -> s * mag >= v end) * mag

    if is_float(v), do: step, else: round(step)
  end
end
