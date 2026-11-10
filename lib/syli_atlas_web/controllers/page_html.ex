defmodule SyliAtlasWeb.PageHTML do
  use SyliAtlasWeb, :html

  embed_templates "page_html/*"

  attr :africa, :map, required: true
  attr :world, :map, default: nil
  attr :from, :integer, required: true
  attr :to, :integer, required: true
  attr :locale, :string, required: true

  @doc "The hero's window: Africa's GDP in current dollars, its change, a sparkline."
  def headline_window(assigns) do
    s = assigns.africa["profile"]["series"]
    ch = assigns.africa["period"]["changes"]

    assigns =
      assign(assigns,
        spark: SyliAtlasWeb.Spark.paths(s["gdp_usd_bn"], assigns.from, assigns.to, 300, 60),
        gdp: PublicData.at(s["gdp_usd_bn"], assigns.to),
        gdp_change: ch["gdp_usd_bn"]
      )

    ~H"""
    <div class="window" aria-live="polite">
      <div class="window-bar"><i></i><i></i><i></i><span>atlas · africa · gdp</span></div>
      <div class="window-body stack gap-3">
        <p class="eyebrow">{gettext("Africa's GDP in current dollars")} · {@to}</p>
        <div class="row gap-2">
          <span class="num headline">{value(@gdp, "gdp_usd_bn", @locale)}</span>
          <span class="pill pill-info">{gettext("%{year} estimated", year: @to)}</span>
        </div>
        <svg
          viewBox="0 0 300 60"
          class="headline-spark"
          role="img"
          aria-label={gettext("Africa's GDP in current dollars, 2015 to 2030")}
        >
          <g class="draw">
            <path d={@spark.past} class="spark-past" />
            <path d={@spark.future} class="spark-future" />
          </g>
          <circle
            :if={@spark.dot}
            class="spark-dot"
            cx={elem(@spark.dot, 0)}
            cy={elem(@spark.dot, 1)}
            r="4"
          />
        </svg>
        <div>
          <.list_row
            label={gettext("In dollars since %{year}", year: @from)}
            value={change(@gdp_change, "gdp_usd_bn", @locale)}
            tone={tone(@gdp_change, "gdp_usd_bn")}
          />
          <.list_row
            :if={@world}
            label={gettext("World, in dollars since %{year}", year: @from)}
            value={change(@world["period"]["changes"]["gdp_usd_bn"], "gdp_usd_bn", @locale)}
          />
        </div>
        <p class="src">{gettext("IMF, at market exchange rates · dashed: projections")}</p>
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
        label={gettext("GDP in dollars") <> " · #{@from} → #{@to}"}
        value={change(@africa["period"]["changes"]["gdp_usd_bn"], "gdp_usd_bn", @locale)}
        tone={tone(@africa["period"]["changes"]["gdp_usd_bn"], "gdp_usd_bn")}
      >
        {@world &&
          gettext("World: %{v}",
            v: change(@world["period"]["changes"]["gdp_usd_bn"], "gdp_usd_bn", @locale)
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
        |> Enum.map(&(&1["period"]["changes"]["gdp_usd_bn"] || 0))
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
        <:col :let={r} label={gettext("GDP in dollars %{from} → %{to}", from: @from, to: @to)}>
          <% c = r["period"]["changes"]["gdp_usd_bn"] %>
          <span class="bar-cell">
            <.bar pct={if(c && @max > 0, do: round(max(c, 0) / @max * 100), else: 0)} />
            <b class={tone(c, "gdp_usd_bn")}>{change(c, "gdp_usd_bn", @locale)}</b>
          </span>
        </:col>
      </.data_table>
    </.card>
    """
  end

  @doc "The time of the last daily check, as stored in the snapshot (ISO 8601)."
  def checked_at(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
      _ -> iso
    end
  end
end
