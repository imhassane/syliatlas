defmodule SyliAtlasWeb.MapComponents do
  @moduledoc """
  The map of Africa and its country panel.

  Every country is a link to its profile, so the map works without
  JavaScript. With it (`assets/js/ui/map.js`), a click shows the country in
  the panel instead: beside the map from 40rem, in a bottom sheet on phones.
  """
  use Phoenix.Component
  use Gettext, backend: SyliAtlasWeb.Gettext

  import SyliAtlasWeb.UI
  alias SyliAtlas.Geo.AfricaMap
  alias SyliAtlasWeb.{Format, MapScale, Paths, RatingComponents, Spark}

  attr :id, :string, required: true
  attr :countries, :list, required: true, doc: "entries of the map snapshot"
  attr :mode, :atom, default: :indicator, values: [:indicator, :regions]
  attr :indicator, :string, default: "gdp"
  attr :selected, :string, default: nil
  attr :focus, :string, default: nil, doc: "region shown in colour (regions mode)"
  attr :locale, :string, required: true
  attr :label, :string, required: true

  def africa_map(assigns) do
    map = AfricaMap.get()
    by_code = Map.new(assigns.countries, &{&1["code"], &1})

    shapes =
      for {code, area} <- Enum.sort_by(map.areas, &elem(&1, 0)) do
        c = by_code[code]

        fill =
          cond do
            c == nil -> nil
            assigns.mode == :regions and assigns.focus not in [nil, c["region"]] -> "q-none"
            assigns.mode == :regions -> "rf-" <> (c["region"] || "none")
            true -> MapScale.class(assigns.indicator, c[value_key(assigns.indicator)])
          end

        %{code: code, area: area, country: c, fill: fill}
      end

    assigns = assign(assigns, map: map, shapes: shapes)

    ~H"""
    <svg
      id={@id}
      class="map reveal"
      viewBox={"0 0 #{@map.width} #{@map.height}"}
      role="group"
      aria-label={@label}
    >
      <%= for s <- @shapes do %>
        <path :if={!s.country} class="q-none no-data" d={s.area.d}>
          <title>{gettext("No separate IMF data")}</title>
        </path>
        <a
          :if={s.country}
          href={href(@mode, s.country, @locale)}
          class={[
            "cty",
            "rg-" <> (s.country["region"] || "none"),
            s.fill,
            s.code == @selected && "is-sel"
          ]}
          data-code={s.code}
          aria-label={s.country["name"]}
        >
          <path d={s.area.d}></path>
          <circle :if={s.area.small} class="isle" cx={s.area.cx} cy={s.area.cy} r="5"></circle>
        </a>
      <% end %>
    </svg>
    """
  end

  # The region's slug comes with the country in the map snapshot (no lookup).
  defp href(:regions, c, locale),
    do: Paths.area(locale, "region", c["region_slug"] || c["region"])

  defp href(_, c, locale), do: Paths.area(locale, "country", c["slug"])

  defp value_key(key), do: key

  attr :key, :string, required: true
  attr :locale, :string, required: true

  def map_legend(assigns) do
    ~H"""
    <ul class="legend" data-map-legend>
      <li :for={{class, label} <- MapScale.legend(@key, @locale)}><i class={class}></i>{label}</li>
      <li><i class="q-none"></i>{gettext("No data")}</li>
    </ul>
    """
  end

  attr :country, :map, required: true
  attr :indicator, :string, required: true
  attr :from, :integer, required: true
  attr :to, :integer, required: true
  attr :locale, :string, required: true

  attr :rating, :map, default: nil, doc: "the country's entry of the ratings document"
  attr :rated, :integer, default: 0

  @doc """
  The selected country. Each value carries `data-field` so the script can
  refill it; the panel is a popover, shown inline from 40rem (`.sheet`).
  """
  def map_panel(assigns) do
    c = assigns.country

    assigns =
      assign(assigns, spark: Spark.paths(c["series"] || [], assigns.from, assigns.to), c: c)

    ~H"""
    <aside
      id="map-panel"
      class="card map-panel sheet"
      popover
      aria-labelledby="map-panel-name"
      aria-live="polite"
    >
      <div class="sheet-head"><span class="sheet-handle" aria-hidden="true"></span></div>
      <div class="map-panel-top">
        <span class="pill p-info" data-field="indicator">
          {MapScale.title(@indicator, @from, @to)} : {MapScale.value_text(@indicator, @c, @locale)}
        </span>
        <div class="js-only map-steps">
          <button
            type="button"
            class="icon-btn"
            data-map-step="-1"
            aria-label={gettext("Previous country in the ranking")}
          >
            <svg
              width="18"
              height="18"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="1.8"
              stroke-linecap="round"
              aria-hidden="true"
            ><path d="M15 6l-6 6 6 6"></path></svg>
          </button>
          <button
            type="button"
            class="icon-btn"
            data-map-step="1"
            aria-label={gettext("Next country in the ranking")}
          >
            <svg
              width="18"
              height="18"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="1.8"
              stroke-linecap="round"
              aria-hidden="true"
            ><path d="M9 6l6 6-6 6"></path></svg>
          </button>
        </div>
      </div>
      <div class="map-panel-body" data-map-body>
        <div class="stack gap-1">
          <p class="eyebrow" data-field="meta">{meta(@c)}</p>
          <h3 id="map-panel-name" class="map-panel-name" data-field="name">{@c["name"]}</h3>
        </div>
        <div class="stack gap-1">
          <span class="big map-panel-change" data-field="gdp" data-value={@c["gdp"]}>
            {Format.value(@c["gdp"], "gdp_usd_bn", @locale)}
          </span>
          <span class="muted small">{gettext("GDP in current dollars, %{year} (IMF)", year: @to)}</span>
        </div>
        <dl class="map-panel-changes single">
          <div>
            <dt>{gettext("In dollars since %{year}", year: @from)}</dt>
            <dd class={Format.tone(@c["gdp_change"], "gdp_usd_bn")} data-field="gdp-change">
              {Format.change(@c["gdp_change"], "gdp_usd_bn", @locale)}
            </dd>
          </div>
        </dl>
        <svg
          viewBox="0 0 260 56"
          class="spark"
          role="img"
          aria-label={gettext("GDP in current dollars, 2015 to 2030")}
        >
          <line
            class="spark-base"
            data-field="spark-base"
            x1={@spark.base_x}
            x2={@spark.base_x}
            y1="0"
            y2="56"
          >
          </line>
          <g class="draw" data-field="spark-line">
            <path class="spark-past" data-field="spark-past" d={@spark.past}></path>
            <path class="spark-future" data-field="spark-future" d={@spark.future}></path>
          </g>
          <circle
            :if={@spark.dot}
            class="spark-dot"
            data-field="spark-dot"
            cx={elem(@spark.dot, 0)}
            cy={elem(@spark.dot, 1)}
            r="4.5"
          >
          </circle>
        </svg>
        <dl class="kv">
          <div>
            <dt>{gettext("GDP per capita %{year}", year: @to)}</dt><dd data-field="gdppc">
              {Format.value(@c["gdppc"], "gdp_per_capita_usd", @locale)}
            </dd>
          </div>
          <div>
            <dt>{gettext("Real growth %{year}", year: @to)}</dt><dd data-field="growth">
              {Format.value(@c["growth"], "real_gdp_growth", @locale)}
            </dd>
          </div>
          <div>
            <dt>{gettext("Inflation %{year}", year: @to)}</dt><dd data-field="inflation">
              {Format.value(@c["inflation"], "inflation", @locale)}
            </dd>
          </div>
          <div>
            <dt>{gettext("Public debt %{year}", year: @to)}</dt><dd data-field="debt">
              {Format.value(@c["debt"], "public_debt_pct_gdp", @locale)}
            </dd>
          </div>
        </dl>
        <a class="map-rating" href={Paths.ratings(@locale)} data-field="rating">
          <span class="map-rating-top">
            <span class="map-rating-title">{gettext("Sovereign rating")}</span>
            <b class="num" data-field="rating-label">{rating_text(@rating).label}</b>
            <span class={["rt-badge", rating_text(@rating).class]} data-field="rating-verdict">
              {rating_text(@rating).verdict}
            </span>
          </span>
          <span class="small muted" data-field="rating-detail">
            {rating_text(@rating, @rated).detail}
          </span>
        </a>
      </div>
      <div class="map-panel-actions">
        <a
          class="btn btn-primary grow"
          data-field="href"
          href={Paths.area(@locale, "country", @c["slug"])}
        >{gettext("See the full profile")} →</a>
        <a class="btn btn-secondary" data-field="compare" href={Paths.compare(@locale, [@c["slug"]])}>{gettext(
          "Compare"
        )}</a>
      </div>
    </aside>
    """
  end

  @doc "What the panel shows of a country's rating (also sent to the script)."
  def rating_text(entry, rated \\ 0)

  def rating_text(%{"band" => band} = entry, rated) when is_binary(band) do
    %{
      label: entry["label"],
      class: RatingComponents.band_class(band),
      verdict: RatingComponents.verdict(band) <> " · " <> RatingComponents.category(band),
      detail:
        Enum.join(
          Enum.reject(
            [RatingComponents.agencies_text(entry), RatingComponents.rank_text(entry, rated)],
            &is_nil/1
          ),
          " · "
        )
    }
  end

  def rating_text(_entry, _rated) do
    %{
      label: "—",
      class: "rt-none",
      verdict: RatingComponents.verdict(nil),
      detail: gettext("None of the three main agencies rates this country")
    }
  end

  @doc "« Region · economy no. 7 of 53 », ranked by GDP in current dollars."
  def meta(c) do
    rank =
      if c["rank"],
        do: gettext("economy no. %{rank} of %{of}", rank: c["rank"], of: c["of"]),
        else: gettext("not ranked")

    Enum.join(Enum.reject([c["region_name"], rank], &is_nil/1), " · ")
  end

  @doc "JSON safe inside a <script> element: no closing tag can appear in it."
  def json_for_script(data), do: data |> Jason.encode!() |> String.replace("</", "<\\/")

  @doc "Everything the script needs to refill the panel and recolour the map."
  def client_data(countries, from, to, locale, ratings \\ nil) do
    rated = (ratings && ratings["rated"]) || 0

    %{
      from: from,
      to: to,
      locale: locale,
      order: Enum.map(countries, & &1["code"]),
      unit: Format.billions(locale),
      indicators:
        Map.new(MapScale.keys(), fn k ->
          {k,
           %{
             title: MapScale.title(k, from, to),
             legend: Enum.map(MapScale.legend(k, locale), fn {c, l} -> [c, l] end)
           }}
        end),
      countries:
        Map.new(countries, fn c ->
          {c["code"],
           %{
             name: c["name"],
             meta: meta(c),
             gdp: c["gdp"],
             series: c["series"],
             href: Paths.area(locale, "country", c["slug"]),
             compare: Paths.compare(locale, [c["slug"]]),
             tones: %{gdp_change: Format.tone(c["gdp_change"], "gdp_usd_bn")},
             text: %{
               gdp: Format.value(c["gdp"], "gdp_usd_bn", locale),
               gdp_change: Format.change(c["gdp_change"], "gdp_usd_bn", locale),
               gdppc: Format.value(c["gdppc"], "gdp_per_capita_usd", locale),
               growth: Format.value(c["growth"], "real_gdp_growth", locale),
               inflation: Format.value(c["inflation"], "inflation", locale),
               debt: Format.value(c["debt"], "public_debt_pct_gdp", locale)
             },
             rating: rating_text(SyliAtlas.Ratings.for_country(ratings, c["code"]), rated),
             classes: Map.new(MapScale.keys(), &{&1, MapScale.class(&1, c[value_key(&1)])}),
             values: Map.new(MapScale.keys(), &{&1, MapScale.value_text(&1, c, locale)})
           }}
        end)
    }
  end

  attr :countries, :list, required: true
  attr :indicator, :string, required: true
  attr :selected, :map, required: true
  attr :from, :integer, required: true
  attr :to, :integer, required: true
  attr :locale, :string, required: true
  attr :ratings, :map, default: nil, doc: "the ratings document"

  @doc "The home section: indicator switch, map, legend and panel."
  def map_section(assigns) do
    ~H"""
    <div class="map-layout" data-map data-selected={@selected["code"]} data-indicator={@indicator}>
      <script type="application/json" id="map-data">
        <%= Phoenix.HTML.raw(json_for_script(client_data(@countries, @from, @to, @locale, @ratings))) %>
      </script>
      <.card class="map-card">
        <div class="map-toolbar">
          <nav class="seg" aria-label={gettext("Map indicator")}>
            <a
              :for={k <- MapScale.keys()}
              href={"?carte=#{k}#carte"}
              data-map-indicator={k}
              aria-current={k == @indicator && "true"}
            >{MapScale.label(k)}</a>
          </nav>
          <form class="map-goto" action={Paths.search(@locale)} method="get">
            <label for="map-goto" class="vh">{gettext("Go to a country")}</label>
            <select id="map-goto" name="q" class="select" data-map-goto>
              <option
                :for={c <- Enum.sort_by(@countries, &SyliAtlas.Geo.Area.normalize(&1["name"]))}
                value={c["name"]}
                data-code={c["code"]}
                selected={c["code"] == @selected["code"]}
              >
                {c["name"]}
              </option>
            </select>
            <button type="submit" class="btn btn-secondary no-js-only">{gettext("Go")}</button>
          </form>
        </div>
        <.africa_map
          id="africa-map"
          countries={@countries}
          indicator={@indicator}
          selected={@selected["code"]}
          locale={@locale}
          label={gettext("Map of Africa: choose a country")}
        />
        <.map_legend key={@indicator} locale={@locale} />
        <p class="src">
          {gettext(
            "Islands are marked with a dot. Western Sahara has no separate IMF data. Source: IMF, World Economic Outlook."
          )}
        </p>
      </.card>
      <.map_panel
        country={@selected}
        indicator={@indicator}
        from={@from}
        to={@to}
        locale={@locale}
        rating={SyliAtlas.Ratings.for_country(@ratings, @selected["code"])}
        rated={(@ratings && @ratings["rated"]) || 0}
      />
    </div>
    """
  end
end
