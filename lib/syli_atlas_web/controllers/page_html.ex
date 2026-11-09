defmodule SyliAtlasWeb.PageHTML do
  use SyliAtlasWeb, :html

  embed_templates "page_html/*"

  attr :africa, :map, required: true
  attr :ssa, :map, default: nil
  attr :world, :map, default: nil
  attr :from, :integer, required: true
  attr :to, :integer, required: true
  attr :locale, :string, required: true

  @doc "The hero's window: Africa's real GDP change with a sparkline."
  def headline_window(assigns) do
    assigns =
      assign(
        assigns,
        :spark,
        spark_path(
          assigns.africa["profile"]["series"]["real_gdp_index"],
          assigns.from,
          assigns.to
        )
      )

    ~H"""
    <div class="window" aria-live="polite">
      <div class="window-bar"><i></i><i></i><i></i><span>atlas · africa · real gdp</span></div>
      <div class="window-body stack gap-3">
        <p class="eyebrow">{gettext("Africa's real GDP")} · {@from} → {@to}</p>
        <div class="row gap-2">
          <span class="num headline">{change(
            @africa["period"]["changes"]["real_gdp_index"],
            "real_gdp_index",
            @locale
          )}</span>
          <span class="pill pill-info">{gettext("%{year} estimated", year: @to)}</span>
        </div>
        <svg
          viewBox="0 0 300 60"
          width="100%"
          height="64"
          role="img"
          aria-label={gettext("Africa's real GDP, 2015 to 2030")}
        >
          <path
            d={@spark.past}
            fill="none"
            style="stroke: var(--c1)"
            stroke-width="2.5"
            stroke-linejoin="round"
          />
          <path
            d={@spark.future}
            fill="none"
            style="stroke: var(--c1)"
            stroke-width="2.5"
            stroke-dasharray="5 4"
          />
          <circle
            :if={@spark.dot}
            cx={elem(@spark.dot, 0)}
            cy={elem(@spark.dot, 1)}
            r="4"
            style="fill: var(--c1)"
          />
        </svg>
        <div>
          <.list_row
            :if={@ssa}
            label={gettext("Sub-Saharan Africa (IMF average)")}
            value={change(@ssa["period"]["changes"]["real_gdp_index"], "real_gdp_index", @locale)}
          />
          <.list_row
            :if={@world}
            label={gettext("World (IMF average)")}
            value={change(@world["period"]["changes"]["real_gdp_index"], "real_gdp_index", @locale)}
          />
        </div>
        <p class="src">
          {gettext("Volume of output, excluding inflation and exchange rates · dashed: projections")}
        </p>
      </div>
    </div>
    """
  end

  attr :africa, :map, required: true
  attr :world, :map, default: nil
  attr :from, :integer, required: true
  attr :to, :integer, required: true
  attr :locale, :string, required: true

  def continent_stats(assigns) do
    assigns = assign(assigns, :s, assigns.africa["profile"]["series"])

    ~H"""
    <.stat_grid>
      <:stat
        label={gettext("Total GDP") <> " · #{@to}"}
        value={value(PublicData.at(@s["gdp_usd_bn"], @to), "gdp_usd_bn", @locale)}
      >
        {gettext("current dollars")}
      </:stat>
      <:stat
        label={gettext("Population") <> " · #{@to}"}
        value={value(PublicData.at(@s["population_m"], @to), "population_m", @locale)}
      >
        {gettext("inhabitants")}
      </:stat>
      <:stat
        label={gettext("Growth") <> " · #{@to}"}
        value={value(PublicData.at(@s["real_gdp_growth"], @to), "real_gdp_growth", @locale)}
      >
        {gettext("weighted average")}
      </:stat>
      <:stat
        label={gettext("Real GDP") <> " · #{@from} → #{@to}"}
        value={change(@africa["period"]["changes"]["real_gdp_index"], "real_gdp_index", @locale)}
        tone={tone(@africa["period"]["changes"]["real_gdp_index"], "real_gdp_index")}
      >
        {@world &&
          gettext("World: %{v}",
            v: change(@world["period"]["changes"]["real_gdp_index"], "real_gdp_index", @locale)
          )}
      </:stat>
    </.stat_grid>
    """
  end

  attr :regions, :list, required: true
  attr :from, :integer, required: true
  attr :to, :integer, required: true
  attr :locale, :string, required: true

  def region_table(assigns) do
    assigns =
      assign(
        assigns,
        :max,
        assigns.regions
        |> Enum.map(&(&1["period"]["changes"]["real_gdp_index"] || 0))
        |> Enum.max(fn -> 1 end)
      )

    ~H"""
    <.card>
      <.data_table
        id="regions"
        caption={gettext("Five regions, very different paths.")}
        rows={@regions}
      >
        <:head :let={r} label={gettext("Region")}>
          <a href={Paths.with_period(Paths.area(@locale, r["profile"]), @from, @to)}>{r["profile"][
            "name"
          ][@locale]}</a>
        </:head>
        <:col :let={r} label={gettext("GDP %{year}", year: @to)}>
          {value(PublicData.at(r["profile"]["series"]["gdp_usd_bn"], @to), "gdp_usd_bn", @locale)}
        </:col>
        <:col :let={r} label={gettext("Share of African GDP")}>
          {number(PublicData.at(r["profile"]["share_of_africa_gdp"], @to), 1, @locale)} %
        </:col>
        <:col :let={r} label={gettext("Population %{year}", year: @to)}>
          {value(PublicData.at(r["profile"]["series"]["population_m"], @to), "population_m", @locale)}
        </:col>
        <:col :let={r} label={gettext("Real GDP %{from} → %{to}", from: @from, to: @to)}>
          <% c = r["period"]["changes"]["real_gdp_index"] %>
          <span class="bar-cell">
            <.bar pct={if(c && @max > 0, do: round(max(c, 0) / @max * 100), else: 0)} />
            <b class={tone(c, "real_gdp_index")}>{change(c, "real_gdp_index", @locale)}</b>
          </span>
        </:col>
      </.data_table>
    </.card>
    """
  end

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
