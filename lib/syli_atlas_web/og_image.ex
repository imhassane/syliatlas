defmodule SyliAtlasWeb.OgImage do
  @moduledoc """
  Share images (Open Graph, 1200 × 630): an SVG drawn from a page's own
  figures, rendered to PNG by resvg (no browser). Six layouts, from the
  mockups « SEO · 5. Images de partage »:

  - `:figure`: a name, one big figure with its caption, pills, a curve
    (country, region, tab of a profile);
  - `:rating`: the rating, each agency's latest decision, the gauge from
    default to AAA with the investment-grade line;
  - `:bars`: the first five of a ranking;
  - `:pair`: two curves side by side (comparison);
  - `:totals`: one total and two figures (community);
  - `:quote`: a price, its change and the session (security, exchange);
  - `:text`: a title and a sentence (every other page).

  Every image names its source and the page's address. Specs are built by
  `SyliAtlasWeb.OgImage.Specs`; this module only draws.
  """

  @w 1200
  @h 630
  @ink "#ffffff"
  @muted "#b8c4d6"
  @accent "#9fb0ff"
  @orange "#ff6b3d"
  @card "#12264a"
  @grid "#1f3560"
  @up "#5fe3a1"
  @down "#ff8a7a"

  @fonts_dir "priv/og/fonts"
  @fontdb_key {__MODULE__, :fontdb}

  @doc "Renders a spec to a PNG binary."
  def render(spec) do
    spec |> svg() |> to_png()
  end

  @doc "The SVG of a spec (the PNG is drawn from it)."
  def svg(spec) do
    [
      ~s(<svg xmlns="http://www.w3.org/2000/svg" width="#{@w}" height="#{@h}" viewBox="0 0 #{@w} #{@h}">),
      defs(),
      ~s(<rect width="#{@w}" height="#{@h}" fill="#0b1a33"/>),
      ~s|<rect x="0" y="618" width="#{@w}" height="12" fill="url(#sun)"/>|,
      brand(spec[:eyebrow]),
      body(spec),
      footer(spec[:url], spec[:source]),
      "</svg>"
    ]
    |> IO.iodata_to_binary()
  end

  defp to_png(svg) do
    Resvg.svg_string_to_png_binary(svg, fontdb: fontdb(), resources_dir: System.tmp_dir!())
  end

  # The fonts are parsed once per node and kept.
  defp fontdb do
    case :persistent_term.get(@fontdb_key, nil) do
      nil ->
        dir = Application.app_dir(:syli_atlas, @fonts_dir)
        {:ok, db} = Resvg.init_fontdb(font_dirs: [dir], skip_system_fonts: true)
        :persistent_term.put(@fontdb_key, db)
        db

      db ->
        db
    end
  end

  # ---------------------------------------------------------------------------
  # Frame

  defp defs do
    ~s(<defs><linearGradient id="sun" x1="0" x2="1">) <>
      ~s(<stop offset="0" stop-color="#ffb547"/><stop offset=".25" stop-color="#ff6b3d"/>) <>
      ~s(<stop offset=".5" stop-color="#f0347a"/><stop offset=".75" stop-color="#8a3ffc"/>) <>
      ~s(<stop offset="1" stop-color="#3b6cff"/></linearGradient></defs>)
  end

  defp brand(eyebrow) do
    [
      ~s|<g transform="translate(72 60)"><rect width="22" height="22" rx="5" fill="#ffffff"/>|,
      ~s(<rect x="26" width="22" height="22" rx="5" fill="#4b3bff"/>),
      ~s(<rect y="26" width="22" height="22" rx="5" fill="#4b3bff"/>),
      ~s(<rect x="26" y="26" width="22" height="22" rx="5" fill="#ff6b3d"/></g>),
      text(138, 96, "syli", size: 34, weight: 600),
      text(213, 96, "atlas", size: 34, weight: 400, fill: @muted),
      if(eyebrow,
        do:
          text(1128, 96, String.upcase(eyebrow),
            size: 20,
            mono: true,
            fill: @accent,
            anchor: "end"
          ),
        else: []
      )
    ]
  end

  # The address (monospace, ~12 px a character) and the source (~10 px)
  # share 1 056 px: the source gives way first.
  defp footer(url, source) do
    url = url && short_url(url)
    room = div(1016 - String.length(url || "") * 12, 10)

    [
      if(url, do: text(72, 584, url, size: 20, mono: true, fill: @muted), else: []),
      if(source && room > 8,
        do: text(1128, 584, fit(source, min(room, 64)), size: 20, fill: @muted, anchor: "end"),
        else: []
      )
    ]
  end

  defp short_url(url), do: url |> String.replace(~r{^https?://}, "") |> fit(52)

  # ---------------------------------------------------------------------------
  # Layouts

  defp body(%{layout: :figure} = s) do
    name_size = name_size(s.title, 64)

    [
      text(72, 222, s.title, size: name_size, weight: 300, spacing: -2),
      text(72, 360, s.figure, size: figure_size(s.figure), weight: 300, spacing: -5),
      text(76, 410, fit(s.caption, 46), size: 26, fill: @muted),
      pills(s[:pills] || [], 72, 456),
      if(s[:series],
        do: curve_card(s.series, s[:series_label], s[:from_label], s[:to_label]),
        else: []
      )
    ]
  end

  defp body(%{layout: :rating} = s) do
    x = fn notch -> 72 + (1128 - 72) * (notch - 1) / 21 end
    score = s[:score]
    line = x.(13)

    [
      text(72, 200, fit(s.title, 48), size: 40, weight: 300, fill: @muted, spacing: -1),
      text(72, 350, s.figure, size: 150, weight: 300, spacing: -5),
      for {agency, i} <- Enum.with_index(Enum.take(s[:lines] || [], 3)) do
        text(380, 268 + i * 44, fit(agency, 42), size: 28)
      end,
      if score do
        [
          rect(72, 420, line - 72, 14, "#3a2a2a", 7),
          rect(line, 420, 1128 - line, 14, "#1d3b6b", 7),
          rect(72, 420, max(x.(score) - 72, 14), 14, @orange, 7),
          ~s(<circle cx="#{r(x.(score))}" cy="427" r="14" fill="#{@orange}" stroke="#0b1a33" stroke-width="5"/>),
          ~s(<line x1="#{r(line)}" x2="#{r(line)}" y1="408" y2="446" stroke="#ffffff" stroke-width="3"/>),
          text(72, 482, s.labels.default, size: 20, fill: @muted),
          text(line, 482, s.labels.investment, size: 20, anchor: "middle"),
          text(1128, 482, "AAA", size: 20, fill: @muted, anchor: "end")
        ]
      else
        []
      end,
      if(s[:note], do: text(72, 530, fit(s.note, 80), size: 22), else: [])
    ]
  end

  defp body(%{layout: :bars} = s) do
    rows = Enum.take(s.rows, 5)
    max = rows |> Enum.map(&abs(elem(&1, 1))) |> Enum.max(fn -> 1 end)

    [
      text(72, 190, fit(s.title, 68),
        size: if(String.length(s.title) > 46, do: 34, else: 44),
        weight: 300,
        spacing: -1
      ),
      for {{name, value, label}, i} <- Enum.with_index(rows) do
        y = 236 + i * 62
        w = max(640 * abs(value) / max(max, 1.0e-9), 4)

        [
          text(72, y + 30, Integer.to_string(i + 1), size: 26, mono: true, fill: @muted),
          text(112, y + 30, fit(name, 18), size: 28),
          rect(380, y + 6, w, 34, if(i == 0, do: @ink, else: @accent), 6),
          text(380 + w + 16, y + 32, label, size: 26, weight: 600)
        ]
      end
    ]
  end

  defp body(%{layout: :pair} = s) do
    [{a_name, a_label, a_series}, {b_name, b_label, b_series}] = s.lines
    all = Enum.filter(a_series ++ b_series, &is_number/1)
    {lo, hi} = bounds(all)

    [
      text(72, 196, fit(s.title, 40), size: 52, weight: 300, spacing: -1.6),
      text(72, 238, "●", size: 24, fill: @accent),
      text(100, 238, fit("#{a_name} #{a_label}", 26), size: 24),
      text(560, 238, "●", size: 24, fill: @orange),
      text(588, 238, fit("#{b_name} #{b_label}", 26), size: 24),
      ~s|<g transform="translate(36 262)">|,
      rect(0, 0, 1128, 280, @card, 16),
      grid_lines(40, 1088, [30, 140, 250]),
      polyline(a_series, 40, 1088, 30, 250, lo, hi, @accent, 6),
      polyline(b_series, 40, 1088, 30, 250, lo, hi, @orange, 5),
      text(40, 272, s.from_label, size: 16, mono: true, fill: @muted),
      text(1088, 272, s.to_label, size: 16, mono: true, fill: @muted, anchor: "end"),
      "</g>"
    ]
  end

  defp body(%{layout: :totals} = s) do
    [
      text(72, 214, fit(s.title, 28), size: 60, weight: 300, spacing: -2),
      text(72, 256, fit(s.subtitle, 70), size: 24, fill: @muted),
      ~s|<g transform="translate(72 300)">|,
      rect(0, 0, 508, 210, @card, 16),
      text(32, 56, s.figure_label, size: 22, fill: @muted),
      text(32, 150, s.figure, size: figure_size(s.figure, 96), weight: 300, spacing: -3),
      text(32, 188, fit(s[:figure_note] || "", 40), size: 20, fill: @muted),
      "</g>",
      for {{label, value}, i} <- Enum.with_index(Enum.take(s.facts, 2)) do
        [
          ~s|<g transform="translate(620 #{300 + i * 114})">|,
          rect(0, 0, 508, 96, @card, 16),
          text(32, 58, fit(label, 20), size: 24, fill: @muted),
          text(476, 62, value, size: 40, weight: 600, anchor: "end"),
          "</g>"
        ]
      end
    ]
  end

  defp body(%{layout: :quote} = s) do
    {tone_bg, tone_fg, arrow} =
      case s[:direction] do
        :up -> {"#103d2a", @up, "▲"}
        :down -> {"#3d1717", @down, "▼"}
        _ -> {@card, @ink, ""}
      end

    [
      text(72, 206, fit(s.title, 26), size: 58, weight: 300, spacing: -1.8),
      text(72, 246, fit(s.subtitle, 64), size: 24, fill: @muted),
      text(72, 388, s.figure, size: figure_size(s.figure, 128), weight: 300, spacing: -4),
      if s[:change] do
        [
          ~s|<g transform="translate(72 428)">|,
          rect(0, 0, 250, 60, tone_bg, 30),
          text(125, 40, String.trim("#{arrow} #{s.change}"),
            size: 30,
            weight: 600,
            fill: tone_fg,
            anchor: "middle"
          ),
          "</g>"
        ]
      else
        []
      end,
      text(346, 468, fit(s[:note] || "", 30), size: 24, fill: @muted),
      ~s|<g transform="translate(760 160)">|,
      rect(0, 0, 368, 330, @card, 16),
      # Label above its value: a long label never runs into the figure.
      for {{label, value}, i} <- Enum.with_index(Enum.take(s[:facts] || [], 4)) do
        y = 46 + i * 80

        [
          text(32, y, fit(label, 30), size: 18, fill: @muted),
          text(32, y + 32, fit(value, 20), size: 28),
          if(i < 3,
            do: ~s(<line x1="32" x2="336" y1="#{y + 50}" y2="#{y + 50}" stroke="#{@grid}"/>),
            else: []
          )
        ]
      end,
      "</g>"
    ]
  end

  defp body(%{layout: :text} = s) do
    title_lines = wrap(s.title, 30) |> Enum.take(3)
    # As many lines as fit above the footer (y 520).
    room = div(520 - (250 + length(title_lines) * 66), 38) + 1
    lines = wrap(s[:text] || "", 62) |> Enum.take(min(4, room))

    [
      for {line, i} <- Enum.with_index(title_lines) do
        text(72, 220 + i * 66, line, size: 56, weight: 300, spacing: -1.6)
      end,
      for {line, i} <- Enum.with_index(lines) do
        text(72, 230 + length(title_lines) * 66 + 20 + i * 38, line, size: 26, fill: @muted)
      end
    ]
  end

  # ---------------------------------------------------------------------------
  # Pieces

  defp pills(pills, x, y) do
    {out, _x} =
      Enum.reduce(Enum.take(pills, 2), {[], x}, fn {label, dot?}, {acc, px} ->
        per_char = if script(label) == :arabic, do: 10.5, else: 13
        w = round(vlen(label) * per_char + if(dot?, do: 76, else: 52))

        # A pill that would run under the curve card is left out.
        piece =
          if px + w > 684 and px > x,
            do: [],
            else: [
              ~s|<g transform="translate(#{px} #{y})">|,
              rect(0, 0, w, 56, @card, 28),
              if(dot?, do: ~s(<circle cx="30" cy="28" r="7" fill="#{@orange}"/>), else: []),
              text(if(dot?, do: 50, else: 26), 37, label, size: 23),
              "</g>"
            ]

        {[acc, piece], if(piece == [], do: px, else: px + w + 16)}
      end)

    out
  end

  defp curve_card(series, label, from_label, to_label) do
    {lo, hi} = bounds(Enum.filter(series, &is_number/1))

    [
      ~s|<g transform="translate(700 160)">|,
      rect(0, 0, 428, 330, @card, 16),
      grid_lines(32, 396, [70, 170, 270]),
      polyline(series, 32, 396, 70, 270, lo, hi, @accent, 6, true),
      text(32, 306, from_label || "", size: 18, mono: true, fill: @muted),
      text(396, 306, to_label || "", size: 18, mono: true, fill: @muted, anchor: "end"),
      text(32, 44, fit(label || "", 34), size: 18, fill: @muted),
      "</g>"
    ]
  end

  defp grid_lines(x0, x1, ys),
    do: for(y <- ys, do: ~s(<line x1="#{x0}" x2="#{x1}" y1="#{y}" y2="#{y}" stroke="#{@grid}"/>))

  # A line through the points that have a value; the last one marked.
  defp polyline(series, x0, x1, y0, y1, lo, hi, color, width, dot? \\ true) do
    n = max(length(series) - 1, 1)
    span = if hi - lo == 0, do: 1, else: hi - lo

    points =
      for {v, i} <- Enum.with_index(series), is_number(v) do
        {x0 + (x1 - x0) * i / n, y1 - (y1 - y0) * (v - lo) / span}
      end

    case points do
      [] ->
        []

      _ ->
        d = points |> Enum.map_join(" L", fn {x, y} -> "#{r(x)} #{r(y)}" end)
        {lx, ly} = List.last(points)

        [
          ~s(<path d="M#{d}" fill="none" stroke="#{color}" stroke-width="#{width}" stroke-linejoin="round" stroke-linecap="round"/>),
          if(dot?,
            do:
              ~s(<circle cx="#{r(lx)}" cy="#{r(ly)}" r="9" fill="#{color}" stroke="#{@card}" stroke-width="4"/>),
            else: []
          )
        ]
    end
  end

  defp bounds([]), do: {0, 1}

  defp bounds(values) do
    {lo, hi} = Enum.min_max(values)
    pad = max((hi - lo) * 0.08, 0.5)
    {lo - pad, hi + pad}
  end

  defp script(content) do
    text = to_string(content)

    cond do
      text =~ ~r/[\x{0600}-\x{06FF}]/u -> :arabic
      text =~ ~r/[\x{3000}-\x{9FFF}]/u -> :han
      true -> :latin
    end
  end

  # Width of a text in Latin characters: a Chinese character is about two.
  defp vlen(text) do
    text
    |> to_string()
    |> String.graphemes()
    |> Enum.reduce(0, fn g, n ->
      if g =~ ~r/^[\x{3000}-\x{9FFF}\x{FF00}-\x{FFEF}]/u, do: n + 1.8, else: n + 1
    end)
  end

  defp rect(x, y, w, h, fill, radius),
    do:
      ~s(<rect x="#{r(x)}" y="#{r(y)}" width="#{r(w)}" height="#{r(h)}" rx="#{radius}" fill="#{fill}"/>)

  defp text(x, y, content, opts) do
    # Text in Arabic or Chinese is drawn with its own Noto font
    # (priv/og/fonts, which also covers Latin), so the whole run is shaped
    # by one font. Hindi pages share their English twin's image
    # (SyliAtlasWeb.Seo): resvg does not shape Devanagari correctly.
    script = script(content)

    family =
      case script do
        :arabic -> "Noto Sans Arabic, Inter Tight"
        :han -> "Noto Sans SC, Inter Tight"
        :latin -> if(opts[:mono], do: "JetBrains Mono", else: "Inter Tight")
      end

    # Arabic text in a left-to-right layout: starts at x like the others.
    content = if script == :arabic, do: "\u200E" <> to_string(content), else: content

    attrs =
      [
        ~s(x="#{r(x)}" y="#{r(y)}"),
        ~s(font-family="#{family}"),
        ~s(font-size="#{opts[:size] || 24}"),
        ~s(font-weight="#{opts[:weight] || if(opts[:mono], do: 500, else: 400)}"),
        ~s(fill="#{opts[:fill] || @ink}"),
        if(opts[:anchor], do: ~s(text-anchor="#{opts[:anchor]}"), else: nil),
        # Letter spacing would break the joined letters of Arabic and Devanagari.
        if(opts[:spacing] && script == :latin,
          do: ~s(letter-spacing="#{opts[:spacing]}"),
          else: nil
        )
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

    ["<text ", attrs, ">", esc(content), "</text>"]
  end

  defp r(n) when is_integer(n), do: Integer.to_string(n)
  defp r(n), do: :erlang.float_to_binary(n * 1.0, decimals: 1)

  defp esc(nil), do: ""

  defp esc(s) do
    s
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  # Long names (Sao Tomé-et-Principe, République centrafricaine) get smaller.
  defp name_size(name, base) do
    case String.length(name || "") do
      n when n > 26 -> round(base * 0.62)
      n when n > 18 -> round(base * 0.8)
      _ -> base
    end
  end

  defp figure_size(figure, base \\ 132) do
    case String.length(figure || "") do
      n when n > 11 -> round(base * 0.6)
      n when n > 8 -> round(base * 0.8)
      _ -> base
    end
  end

  @doc false
  def fit(nil, _max), do: ""

  def fit(s, max) do
    if String.length(s) <= max, do: s, else: String.slice(s, 0, max - 1) <> "…"
  end

  @doc false
  def wrap(text, width) do
    text
    |> String.split(~r/\s+/u, trim: true)
    |> Enum.reduce([], fn word, acc ->
      case acc do
        [line | rest] ->
          if String.length(line) + 1 + String.length(word) <= width,
            do: [line <> " " <> word | rest],
            else: [word, line | rest]

        [] ->
          [word]
      end
    end)
    |> Enum.reverse()
  end
end
