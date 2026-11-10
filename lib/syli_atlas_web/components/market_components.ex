defmodule SyliAtlasWeb.MarketComponents do
  @moduledoc """
  Pieces of the market pages: price and change formats, the scrolling band
  of indices, the index chart, the source block, and the « stock exchange »
  block of a country page. Prices arrive as strings (exact decimals).
  """
  use Phoenix.Component
  use Gettext, backend: SyliAtlasWeb.Gettext
  import SyliAtlasWeb.Format, only: [number: 3]
  alias SyliAtlasWeb.Paths

  @nbsp " "

  # Formats ------------------------------------------------------------------

  def to_f(nil), do: nil
  def to_f(n) when is_number(n), do: n * 1.0

  def to_f(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> nil
    end
  end

  @doc "A price or an index level: no decimals when whole, two otherwise."
  def price(nil, locale), do: na(locale)

  def price(value, locale) when is_binary(value) do
    f = to_f(value)
    decimals = if String.contains?(value, ".") and f != Float.round(f), do: 2, else: 0
    decimals = if f < 10 and f != Float.round(f), do: 2, else: decimals
    number(f, decimals, locale)
  end

  def price(value, locale) when is_number(value), do: price(to_string(value), locale)

  @doc "A signed change in percent with its arrow: « ▲ +1,44 % »."
  def pct(nil, locale), do: na(locale)

  def pct(value, locale) do
    f = to_f(value)

    {arrow, sign} =
      cond do
        f > 0 -> {"▲", "+"}
        f < 0 -> {"▼", ""}
        true -> {"■", ""}
      end

    arrow <> " " <> sign <> number(f, 2, locale) <> @nbsp <> "%"
  end

  @doc "A change since 1 January (no arrow)."
  def ytd(nil, locale), do: na(locale)

  def ytd(value, locale) do
    f = to_f(value)
    if(f > 0, do: "+", else: "") <> number(f, 1, locale) <> @nbsp <> "%"
  end

  def tone(nil), do: "muted"

  def tone(value) do
    f = to_f(value)

    cond do
      f > 0 -> "up"
      f < 0 -> "down"
      true -> "muted"
    end
  end

  @doc "An amount in a currency, shortened: « 3,25 Md XOF », « 160,8 M XOF »."
  def amount(nil, _currency, locale), do: na(locale)

  def amount(value, currency, locale) do
    {v, unit} = scale(value * 1.0, locale)
    decimals = if unit == "", do: 0, else: if(v >= 100, do: 1, else: 2)
    String.trim(number(v, decimals, locale) <> @nbsp <> unit) <> @nbsp <> currency
  end

  @doc "An amount in dollars, shortened: « ≈ 5,5 M$ »."
  def usd(nil, _locale), do: nil

  def usd(value, locale) do
    {v, unit} = scale(value * 1.0, locale)
    decimals = if v >= 100, do: 0, else: 1
    "≈" <> @nbsp <> number(v, decimals, locale) <> @nbsp <> unit <> "$"
  end

  defp scale(v, locale) do
    billion = if locale == "en", do: "bn", else: "Md"

    cond do
      abs(v) >= 1.0e9 -> {v / 1.0e9, billion}
      abs(v) >= 1.0e6 -> {v / 1.0e6, "M"}
      abs(v) >= 1.0e4 -> {v / 1.0e3, "k"}
      true -> {v, ""}
    end
  end

  def integer(nil, locale), do: na(locale)
  def integer(n, locale), do: number(n * 1.0, 0, locale)

  @months_fr ~w(janv. févr. mars avr. mai juin juil. août sept. oct. nov. déc.)
  @months_en ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

  @doc "« 9 nov. 2026 » / « 9 Nov 2026 »; without the year when `year: false`."
  def day(iso, locale, opts \\ [])
  def day(nil, locale, _opts), do: na(locale)

  def day(iso, locale, opts) do
    case Date.from_iso8601(String.slice(iso, 0, 10)) do
      {:ok, d} ->
        months = if locale == "en", do: @months_en, else: @months_fr
        base = "#{d.day} #{Enum.at(months, d.month - 1)}"
        if Keyword.get(opts, :year, true), do: base <> " #{d.year}", else: base

      _ ->
        iso
    end
  end

  def region_label("west_africa"), do: gettext("West Africa")
  def region_label("north_africa"), do: gettext("North Africa")
  def region_label("central_africa"), do: gettext("Central Africa")
  def region_label("east_africa"), do: gettext("East Africa")
  def region_label("southern_africa"), do: gettext("Southern Africa")
  def region_label(_), do: ""

  defp na("en"), do: "n/a"
  defp na(_), do: "n.d."

  # Freshness ------------------------------------------------------------------

  attr :index, :map, required: true
  attr :locale, :string, required: true

  @doc "The state of an index: its date, or why there is none."
  def freshness(assigns) do
    ~H"""
    <span :if={missing?(@index)} class="pill pill-warn">
      {gettext("index not provided")}
    </span>
    <span
      :if={@index["flags"]["stale"]}
      class="pill pill-warn"
      title={gettext("No session received for more than two business days")}
    >
      {day(@index["flags"]["stale_since"] || @index["date"], @locale, year: false)} · {gettext("old")}
    </span>
    <span :if={@index["date"] && !@index["flags"]["stale"] && !missing?(@index)} class="pill pill-ok">
      {day(@index["date"], @locale, year: false)}
    </span>
    """
  end

  defp missing?(index), do: index["flags"]["missing"] == true and is_nil(index["value"])

  attr :value, :any, required: true
  attr :locale, :string, required: true
  attr :suspect, :boolean, default: false

  @doc "A change with its arrow and colour, and the « to check » badge when suspect."
  def change_cell(assigns) do
    ~H"""
    <b class={["num", tone(@value)]}>{pct(@value, @locale)}</b>
    <span
      :if={@suspect}
      class="pill pill-warn no-dot market-check"
      title={gettext("Same as the change since 1 January given by the source")}
    >
      {gettext("to check")}
    </span>
    """
  end

  # The scrolling band -----------------------------------------------------------

  attr :exchanges, :list, required: true
  attr :locale, :string, required: true

  @doc """
  Indices at the last close, scrolling. The list is written twice so the
  loop is seamless; the copy is hidden from screen readers. Still when the
  reader asked for less motion, paused on hover.
  """
  def ticker_band(assigns) do
    assigns =
      assign(assigns, :items, Enum.filter(assigns.exchanges, &(&1["index"]["value"] != nil)))

    ~H"""
    <div
      :if={@items != []}
      class="ticker"
      role="region"
      aria-label={gettext("Indices at the last close")}
    >
      <div class="ticker-track">
        <ul class="ticker-list">
          <li :for={x <- @items}>
            <a href={Paths.exchange(@locale, x["exchange"]["code"])}>
              <b>{x["exchange"]["short_name"]}</b>
              <span class="muted">{price(x["index"]["value"], @locale)}</span>
              <span class={tone(x["index"]["change_pct"])}>{pct(x["index"]["change_pct"], @locale)}</span>
            </a>
          </li>
        </ul>
        <ul class="ticker-list" aria-hidden="true">
          <li :for={x <- @items}>
            <a href={Paths.exchange(@locale, x["exchange"]["code"])} tabindex="-1">
              <b>{x["exchange"]["short_name"]}</b>
              <span class="muted">{price(x["index"]["value"], @locale)}</span>
              <span class={tone(x["index"]["change_pct"])}>{pct(x["index"]["change_pct"], @locale)}</span>
            </a>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  # Index chart --------------------------------------------------------------------

  attr :id, :string, required: true
  attr :history, :list, required: true, doc: "[[iso_date, value_string], …], oldest first"
  attr :label, :string, required: true
  attr :locale, :string, required: true

  @doc """
  The index over time, drawn from the sessions received. A gap of more than
  a week between two sessions breaks the line, so missing data never looks
  like a straight move.
  """
  def index_chart(assigns) do
    assigns = assign(assigns, :chart, chart(assigns.history))

    ~H"""
    <figure class="market-chart" id={@id}>
      <svg viewBox="0 0 760 260" role="img" aria-label={@label}>
        <g class="grid-lines">
          <line :for={t <- @chart.ticks} x1="56" x2="744" y1={t.y} y2={t.y} />
        </g>
        <g class="axis-labels">
          <text :for={t <- @chart.ticks} x="48" y={t.y + 4} text-anchor="end">
            {price(t.label, @locale)}
          </text>
          <text x="56" y="252">{day(@chart.first, @locale)}</text>
          <text x="744" y="252" text-anchor="end">{day(@chart.last, @locale)}</text>
        </g>
        <path :for={d <- @chart.paths} d={d} class="line" />
        <circle cx={@chart.end_x} cy={@chart.end_y} r="4.5" class="dot" />
      </svg>
      <figcaption :if={@chart.gaps > 0} class="small muted">
        {ngettext(
          "One stretch without data: the line is broken there.",
          "%{count} stretches without data: the line is broken there.",
          @chart.gaps
        )}
      </figcaption>
    </figure>
    """
  end

  @doc false
  def chart(history) do
    points =
      for [d, v] <- history, f = to_f(v), is_number(f), do: {Date.from_iso8601!(d), f}

    {first, _} = List.first(points)
    {last, _} = List.last(points)
    span = max(Date.diff(last, first), 1)
    values = Enum.map(points, &elem(&1, 1))
    {lo, hi} = {Enum.min(values), Enum.max(values)}
    pad = max((hi - lo) * 0.08, hi * 0.002)
    {lo, hi} = {lo - pad, hi + pad}
    x = fn d -> 56 + Date.diff(d, first) / span * 688 end
    y = fn v -> 16 + (hi - v) / (hi - lo) * 208 end

    segments =
      points
      |> Enum.chunk_while(
        [],
        fn
          p, [] ->
            {:cont, [p]}

          {d, _} = p, [{prev, _} | _] = acc ->
            if Date.diff(d, prev) > 7,
              do: {:cont, Enum.reverse(acc), [p]},
              else: {:cont, [p | acc]}
        end,
        fn acc -> {:cont, Enum.reverse(acc), []} end
      )

    paths =
      for seg <- segments do
        seg
        |> Enum.with_index()
        |> Enum.map_join(" ", fn {{d, v}, i} ->
          if(i == 0, do: "M", else: "L") <> fmt(x.(d)) <> " " <> fmt(y.(v))
        end)
        |> then(fn path -> if length(seg) == 1, do: path <> " h0.1", else: path end)
      end

    step = (hi - lo) / 3

    ticks =
      for i <- 0..3 do
        v = lo + step * i
        %{y: fmt(y.(v)), label: Float.round(v, if(v >= 100, do: 0, else: 2))}
      end

    {_, end_v} = List.last(points)

    %{
      paths: paths,
      ticks: ticks,
      first: Date.to_iso8601(first),
      last: Date.to_iso8601(last),
      end_x: fmt(x.(last)),
      end_y: fmt(y.(end_v)),
      gaps: length(segments) - 1
    }
  end

  defp fmt(n), do: :erlang.float_to_binary(n * 1.0, decimals: 1)

  # Sources --------------------------------------------------------------------------

  attr :sources, :list, required: true
  attr :date, :string, default: nil
  attr :locale, :string, required: true

  @doc "Where the figures come from: every source, its role, its link."
  def market_sources(assigns) do
    ~H"""
    <ul class="market-sources">
      <li :for={s <- @sources}>
        <span class={["pill", if(s["rank"] == 1, do: "pill-ok", else: "pill-neutral")]}>
          {if s["rank"] == 1, do: gettext("Used"), else: gettext("Backup")}
        </span>
        <span>
          <a :if={s["url"]} href={s["url"]} rel="noopener">{s["name"]}</a>
          <span :if={!s["url"]}>{s["name"]}</span>
          <span class="muted">· {source_kind(s["kind"])}</span>
        </span>
      </li>
    </ul>
    """
  end

  def source_kind("aggregator"), do: gettext("market data aggregator")
  def source_kind("official"), do: gettext("the exchange's official list")
  def source_kind(_), do: gettext("other source")

  @doc "« Data: Mansa Markets · close of 9 November 2026 »."
  def attribution(sources, date, locale) do
    names = sources |> Enum.filter(&(&1["rank"] == 1)) |> Enum.map_join(", ", & &1["name"])

    if date do
      gettext("Data: %{sources} · close of %{date} · end of day, not live",
        sources: names,
        date: day(date, locale)
      )
    else
      gettext("Data: %{sources} · end of day, not live", sources: names)
    end
  end

  # Country page block ------------------------------------------------------------------

  attr :exchanges, :list, required: true, doc: "from SyliAtlas.Market.for_country/1"
  attr :name, :string, required: true
  attr :locale, :string, required: true

  def country_market(assigns) do
    ~H"""
    <section class="section" id="market">
      <div class="wrap stack gap-6">
        <div :for={x <- @exchanges} class="stack gap-4">
          <div class="head-row">
            <div class="section-head">
              <p class="eyebrow">{gettext("Stock exchange")}</p>
              <h2 class="h1">
                {gettext("%{country} on the %{exchange}",
                  country: @name,
                  exchange: x["exchange"]["short_name"]
                )}
              </h2>
              <p :if={x["regional"]} class="lead">
                {gettext(
                  "The country has no national exchange: its companies are listed on the %{exchange}, the regional exchange shared by %{count} countries.",
                  exchange: x["exchange"]["short_name"],
                  count: length(x["exchange"]["countries"])
                )}
              </p>
            </div>
            <div class="head-actions">
              <a class="btn btn-secondary" href={Paths.exchange(@locale, x["exchange"]["code"])}>
                {gettext("The %{exchange} page", exchange: x["exchange"]["short_name"])} →
              </a>
            </div>
          </div>
          <div class="grid grid-2">
            <dl class="stats stats-2">
              <div>
                <dt>{x["exchange"]["index_name"] || gettext("Main index")}</dt>
                <dd class="big">{price(x["index"]["value"], @locale)}</dd>
                <dd class={["small", tone(x["index"]["change_pct"])]}>
                  {pct(x["index"]["change_pct"], @locale)}
                  <span :if={x["index"]["date"]} class="muted">
                    · {day(x["index"]["date"], @locale)}
                  </span>
                </dd>
              </div>
              <div>
                <dt>{gettext("Listed securities")}</dt>
                <dd class="big">{x["exchange"]["listed"]}</dd>
                <dd class="small muted">{x["exchange"]["currency"]}</dd>
              </div>
            </dl>
            <div :if={x["top"] != []} class="card">
              <div class="pad">
                <h3 class="h2">{gettext("Most traded local companies")}</h3>
              </div>
              <ol class="rank-list">
                <li :for={{s, i} <- Enum.with_index(x["top"], 1)}>
                  <span class="num subtle">{i}</span>
                  <a href={Paths.security(@locale, x["exchange"]["code"], s["ticker"])}>{s["name"]}</a>
                  <b class={["num", tone(s["change_pct"])]}>{pct(s["change_pct"], @locale)}</b>
                </li>
              </ol>
            </div>
          </div>
          <p class="src">
            {attribution(x["sources"] || [], x["index"]["date"], @locale)} · {gettext(
              "information, not investment advice"
            )}
          </p>
        </div>
      </div>
    </section>
    """
  end
end
