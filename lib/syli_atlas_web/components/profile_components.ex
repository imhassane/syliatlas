defmodule SyliAtlasWeb.ProfileComponents do
  @moduledoc """
  The frame of a country profile split into tabs: the tab bar, the
  overview (one card per tab, two or three figures each) and the related
  links at the bottom of every tab. Each tab has its own URL
  (`SyliAtlasWeb.Paths.area_tab/3`); a tab without data does not exist.
  """
  use Phoenix.Component
  use Gettext, backend: SyliAtlasWeb.Gettext

  import SyliAtlasWeb.Format, only: [value: 3, change: 3, number: 3, names: 2]
  alias SyliAtlasWeb.{Paths, PublicData, WorldBankComponents, TradeComponents}
  alias SyliAtlas.Economy.Communities

  def tab_label(:overview), do: gettext("Overview")
  def tab_label(:economy), do: gettext("Economy")
  def tab_label(:finances), do: gettext("Finances and debt")
  def tab_label(:trade), do: gettext("Trade")
  def tab_label(:society), do: gettext("Society")
  def tab_label(:markets), do: gettext("Markets and rating")

  # Header of a detail page ------------------------------------------------

  attr :crumbs, :list, required: true, doc: "{label, href} tuples; the last one is this page"
  attr :title, :string, required: true, doc: "the H1"
  attr :suffix, :string, default: nil, doc: "the open tab, after the name (hidden on a phone)"
  attr :tag, :string, default: nil, doc: "a code shown after the name (ticker)"
  attr :subtitle, :string, default: nil, doc: "a full name, under the title"
  attr :kpis_id, :string, default: "head-kpis"
  attr :class, :string, default: nil

  slot :mark, doc: "the flag, or a tile (UI.flag/1, monogram/1, region_mark/1)"
  slot :chips, doc: "what the page belongs to, as pills"
  slot :actions, doc: "follow and alert"

  slot :kpi, doc: "a key figure; its inner block is the line under the value" do
    attr :id, :string, required: true
    attr :label, :string, required: true
    attr :value, :string, required: true
    attr :tone, :any
    attr :href, :string
  end

  @doc """
  Header shared by every detail page (country, region, community, exchange,
  security): breadcrumb; mark, name and actions on one line, the mark and the
  actions centred on the name; under the name, the full name and the pills;
  then a strip of key figures.
  """
  def entity_head(assigns) do
    assigns = assign(assigns, :kpi_count, length(assigns.kpi))

    ~H"""
    <div class={["entity-head", @class]}>
      <nav aria-label={gettext("Breadcrumb")}>
        <ol class="crumbs">
          <%= for {{label, href}, i} <- Enum.with_index(@crumbs) do %>
            <li :if={i < length(@crumbs) - 1}><a href={href}>{label}</a></li>
            <li :if={i == length(@crumbs) - 1} aria-current="page">{label}</li>
          <% end %>
        </ol>
      </nav>
      <div class={["entity-id", @mark == [] && "entity-id-plain"]}>
        <div :if={@mark != []} class="entity-mark-slot">{render_slot(@mark)}</div>
        <div class="entity-title">
          <h1 class="entity-name">
            {@title}<span :if={@suffix} class="entity-name-tab"> · {@suffix}</span>
          </h1>
          <span :if={@tag} class="entity-tag mono">{@tag}</span>
        </div>
        <div :if={@actions != []} class="entity-actions">{render_slot(@actions)}</div>
        <div :if={@subtitle || @chips != []} class="entity-meta">
          <p :if={@subtitle} class="entity-subtitle">{@subtitle}</p>
          <div :if={@chips != []} class="entity-chips">{render_slot(@chips)}</div>
        </div>
      </div>
      <ul :if={@kpi != []} class={["card entity-kpis", "entity-kpis-#{@kpi_count}"]} id={@kpis_id}>
        <li :for={k <- @kpi}>
          <a :if={k[:href]} href={k.href} id={"kpi-#{k.id}"} class="entity-kpi">
            <span class="entity-kpi-label">{k.label}</span>
            <span class={["num entity-kpi-value", k[:tone]]}>{k.value}</span>
            <span class="entity-kpi-sub">{render_slot(k)}</span>
          </a>
          <div :if={!k[:href]} id={"kpi-#{k.id}"} class="entity-kpi">
            <span class="entity-kpi-label">{k.label}</span>
            <span class={["num entity-kpi-value", k[:tone]]}>{k.value}</span>
            <span class="entity-kpi-sub">{render_slot(k)}</span>
          </div>
        </li>
      </ul>
    </div>
    """
  end

  attr :text, :string, required: true, doc: "a short name or a ticker (up to six letters)"

  @doc "A tile with a short name, where a page has no flag (exchange, security, community)."
  def monogram(assigns) do
    ~H"""
    <span
      class={["entity-mark mono", String.length(@text) > 4 && "entity-mark-long"]}
      aria-hidden="true"
    >
      {@text}
    </span>
    """
  end

  @doc "The tile of a region or of the continent: a globe."
  def region_mark(assigns) do
    ~H"""
    <span class="entity-mark" aria-hidden="true">
      <svg
        width="26"
        height="26"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="1.6"
        focusable="false"
      >
        <circle cx="12" cy="12" r="9"></circle>
        <ellipse cx="12" cy="12" rx="4" ry="9"></ellipse>
        <path d="M3.5 9h17M3.5 15h17"></path>
      </svg>
    </span>
    """
  end

  @doc "The tile of an economic community: linked circles."
  def community_mark(assigns) do
    ~H"""
    <span class="entity-mark" aria-hidden="true">
      <svg
        width="26"
        height="26"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="1.6"
        focusable="false"
      >
        <circle cx="12" cy="5.5" r="2.5"></circle>
        <circle cx="5.5" cy="17.5" r="2.5"></circle>
        <circle cx="18.5" cy="17.5" r="2.5"></circle>
        <path d="M10.8 7.7 6.7 15.3M13.2 7.7l4.1 7.6M8 17.5h8"></path>
      </svg>
    </span>
    """
  end

  attr :ctx, :map, required: true, doc: "everything the profile knows (see AreaController)"
  attr :region, :any, default: nil
  attr :heading, :string, required: true
  attr :tab_name, :string, default: nil
  attr :path, :string, required: true

  @doc """
  Header of a country profile, the same on every tab: breadcrumb, flag, name,
  region, communities and currency, follow and alert; then six key figures,
  each opening its tab. The tab bar (with the period) follows, sticky.
  """
  def country_head(assigns) do
    ctx = assigns.ctx
    locale = ctx.locale
    suffix = String.replace_prefix(assigns.heading, ctx.name, "") |> String.trim_leading(" · ")
    region = assigns.region

    crumbs =
      [{"Syli Atlas", Paths.home(locale)}] ++
        if(region,
          do: [{SyliAtlas.Geo.Area.name(region, locale), Paths.area(locale, region)}],
          else: []
        ) ++
        if(ctx.tab != :overview,
          do: [{ctx.name, Paths.area(locale, ctx.area)}, {assigns.tab_name, nil}],
          else: [{ctx.name, nil}]
        )

    assigns =
      assign(assigns,
        name: ctx.name,
        area: ctx.area,
        locale: locale,
        crumbs: crumbs,
        suffix: if(suffix in ["", assigns.heading], do: nil, else: suffix),
        kpis: head_kpis(ctx)
      )

    ~H"""
    <.entity_head
      crumbs={@crumbs}
      title={@name}
      suffix={@suffix}
      kpis_id="country-kpis"
      class="country-head"
    >
      <:mark><SyliAtlasWeb.UI.flag code={@area.code} size="lg" /></:mark>
      <:actions>
        <SyliAtlasWeb.AccountComponents.follow
          kind="area"
          ref={@area.code}
          locale={@locale}
          path={@path}
          alert_area={@area.code}
        />
        <.data_menu ctx={@ctx} />
      </:actions>
      <:chips>
        <a :if={@region} class="pill pill-neutral no-dot" href={Paths.area(@locale, @region)}>
          {SyliAtlas.Geo.Area.name(@region, @locale)}
        </a>
        <a
          :for={c <- @ctx.communities}
          class="pill pill-neutral no-dot"
          href={Paths.community(@locale, SyliAtlas.Locales.pick(c.slug, @locale))}
        >
          {SyliAtlas.Locales.pick(c.short, @locale)}
        </a>
        <a
          :if={@ctx.currency}
          class="pill pill-neutral no-dot"
          href={Paths.area_tab(@locale, @area, :finances) <> @ctx.period_query <> "#monnaie"}
        >
          {@ctx.currency.name} ({@ctx.currency.code})
        </a>
      </:chips>
      <:kpi
        :for={k <- @kpis}
        id={k.id}
        label={k.label}
        value={k.value}
        tone={k.tone}
        href={k.href}
      >
        {k.sub}
      </:kpi>
    </.entity_head>
    """
  end

  attr :ctx, :map, required: true, doc: "everything the profile knows (see AreaController)"

  @doc """
  « Data » and « Embed » in the profile's header. Data opens a menu (a
  `<details>` panel: no JavaScript, keyboard-friendly) with the files of the
  period shown (SyliAtlasWeb.ExportController); Embed leads to the page
  that writes the code for an article (SyliAtlasWeb.EmbedController).
  """
  def data_menu(assigns) do
    ctx = assigns.ctx
    file = &Paths.area_data(ctx.locale, ctx.area, &1, ctx.from, ctx.to)

    files = [
      %{
        id: "csv",
        name: "CSV",
        href: file.(:csv),
        hint: gettext("opens in Excel, LibreOffice"),
        # A sheet of rows and columns.
        icon: [
          "M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z",
          "M14 3v5h5",
          "M8.5 12.5h7M8.5 16h7M12 12.5V19"
        ]
      },
      %{
        id: "xlsx",
        name: "Excel",
        href: file.(:xlsx),
        hint: gettext("a sheet of figures, a sheet of sources"),
        # A grid: the workbook.
        icon: [
          "M5 4h14a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1z",
          "M4 9.5h16M4 14.5h16M9.5 4v16"
        ]
      },
      %{
        id: "json",
        name: "JSON",
        href: file.(:json),
        hint: gettext("the format of the API"),
        # Braces: data for code.
        icon: [
          "M8 4c-2 0-2.5 1-2.5 3v2c0 1.5-.8 2.5-2 3 1.2.5 2 1.5 2 3v2c0 2 .5 3 2.5 3",
          "M16 4c2 0 2.5 1 2.5 3v2c0 1.5.8 2.5 2 3-1.2.5-2 1.5-2 3v2c0 2-.5 3-2.5 3"
        ]
      }
    ]

    assigns = assign(assigns, files: files)

    ~H"""
    <details class="data-menu" id="data-menu" data-nav-menu>
      <summary class="btn btn-secondary btn-sm">
        <svg
          width="16"
          height="16"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="1.8"
          stroke-linecap="round"
          stroke-linejoin="round"
          aria-hidden="true"
        ><path d="M12 4v11"></path><path d="M7 10l5 5 5-5"></path><path d="M5 20h14"></path></svg>
        <span>{gettext("Data")}</span>
      </summary>
      <div class="data-menu-panel">
        <p class="eyebrow">
          {gettext("IMF figures, %{from} → %{to}", from: @ctx.from, to: @ctx.to)}
        </p>
        <ul role="list">
          <li :for={f <- @files}>
            <a href={f.href} download id={"data-" <> f.id}>
              <span class="data-menu-icon" aria-hidden="true">
                <svg
                  width="20"
                  height="20"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="1.8"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                >
                  <path :for={d <- f.icon} d={d}></path>
                </svg>
              </span>
              <span class="data-menu-text">
                <b>{f.name} <span class="sr-only">{gettext("(file)")}</span></b>
                <span class="small muted">{f.hint}</span>
              </span>
            </a>
          </li>
        </ul>
        <p class="small muted">
          {gettext(
            "Each file names its source and the sentence to cite. Stock prices are not included."
          )}
        </p>
      </div>
    </details>
    <a class="btn btn-quiet btn-sm" href={Paths.area_embed(@ctx.locale, @ctx.area)} id="embed-link">
      <svg
        width="16"
        height="16"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="1.8"
        stroke-linecap="round"
        stroke-linejoin="round"
        aria-hidden="true"
      ><path d="M8 7l-5 5 5 5"></path><path d="M16 7l5 5-5 5"></path></svg>
      <span>{gettext("Embed")}</span>
    </a>
    """
  end

  attr :ctx, :map, required: true, doc: "everything the profile knows (see AreaController)"
  attr :region, :any, default: nil, doc: "the continent, for the breadcrumb"
  attr :members, :integer, default: 0, doc: "how many countries the area groups"
  attr :path, :string, required: true

  @doc """
  Header of a region or of the continent, built like a country's: a globe
  where a country has its flag, then key figures that lead to the sections
  of the page.
  """
  def region_head(assigns) do
    ctx = assigns.ctx
    locale = ctx.locale

    crumbs =
      [{"Syli Atlas", Paths.home(locale)}] ++
        if(assigns.region,
          do: [
            {SyliAtlas.Geo.Area.name(assigns.region, locale), Paths.area(locale, assigns.region)}
          ],
          else: []
        ) ++ [{ctx.name, nil}]

    assigns = assign(assigns, crumbs: crumbs, kpis: region_kpis(ctx, assigns.members))

    ~H"""
    <.entity_head crumbs={@crumbs} title={@ctx.name} kpis_id="region-kpis" class="region-head">
      <:mark><.region_mark /></:mark>
      <:actions>
        <SyliAtlasWeb.AccountComponents.follow
          kind="area"
          ref={@ctx.area.code}
          locale={@ctx.locale}
          path={@path}
        />
        <.data_menu ctx={@ctx} />
      </:actions>
      <:chips>
        <span class="pill pill-neutral no-dot">{area_kind_label(@ctx.area.kind)}</span>
        <a :if={@members > 0} class="pill pill-neutral no-dot" href="#members">
          {ngettext("%{count} country", "%{count} countries", @members)}
        </a>
      </:chips>
      <:kpi
        :for={k <- @kpis}
        id={k.id}
        label={k.label}
        value={k.value}
        tone={k.tone}
        href={k.href}
      >
        {k.sub}
      </:kpi>
    </.entity_head>
    """
  end

  defp area_kind_label("continent"), do: gettext("Continent")
  defp area_kind_label(_), do: gettext("African Union region")

  defp region_kpis(ctx, members) do
    l = ctx.locale
    series = ctx.profile["series"]
    changes = ctx.data["period"]["changes"]
    at = fn k -> PublicData.at(series[k], ctx.to) end
    since = gettext("since %{year}", year: ctx.from)

    [
      %{
        id: "gdp",
        label: gettext("GDP %{year}", year: ctx.to),
        value: value(at.("gdp_usd_bn"), "gdp_usd_bn", l),
        sub: change(changes["gdp_usd_bn"], "gdp_usd_bn", l) <> " " <> since,
        tone: nil,
        href: "#economie"
      },
      %{
        id: "growth",
        label: gettext("Growth %{year}", year: ctx.to),
        value: value(at.("real_gdp_growth"), "real_gdp_growth", l),
        sub:
          gettext("real GDP %{change} %{since}",
            change: change(changes["real_gdp_index"], "real_gdp_index", l),
            since: since
          ),
        tone: SyliAtlasWeb.Format.tone(at.("real_gdp_growth"), "real_gdp_growth"),
        href: "#economie"
      },
      %{
        id: "gdp-per-capita",
        label: gettext("GDP per capita"),
        value: value(at.("gdp_per_capita_usd"), "gdp_per_capita_usd", l),
        sub: to_string(ctx.to),
        tone: nil,
        href: "#economie"
      },
      %{
        id: "debt",
        label: gettext("Public debt"),
        value: value(at.("public_debt_pct_gdp"), "public_debt_pct_gdp", l),
        sub: gettext("of GDP, %{year}", year: ctx.to),
        tone: nil,
        href: "#finances"
      },
      %{
        id: "population",
        label: gettext("Population"),
        value: value(at.("population_m"), "population_m", l),
        sub: to_string(ctx.to),
        tone: nil,
        href: if(members > 0, do: "#members", else: "#economie")
      },
      %{
        id: "inflation",
        label: gettext("Inflation"),
        value: value(at.("inflation"), "inflation", l),
        sub: to_string(ctx.to),
        tone: nil,
        href: "#economie"
      }
    ]
  end

  defp head_kpis(ctx) do
    l = ctx.locale
    series = ctx.profile["series"]
    changes = ctx.data["period"]["changes"]
    at = fn k -> PublicData.at(series[k], ctx.to) end

    tab = fn t ->
      Paths.area_tab(l, ctx.area, if(t in ctx.tabs, do: t, else: :overview)) <> ctx.period_query
    end

    since = gettext("since %{year}", year: ctx.from)
    rating = ctx.rating

    [
      %{
        id: "gdp",
        label: gettext("GDP %{year}", year: ctx.to),
        value: value(at.("gdp_usd_bn"), "gdp_usd_bn", l),
        sub: change(changes["gdp_usd_bn"], "gdp_usd_bn", l) <> " " <> since,
        tone: nil,
        href: tab.(:economy)
      },
      %{
        id: "growth",
        label: gettext("Growth %{year}", year: ctx.to),
        value: value(at.("real_gdp_growth"), "real_gdp_growth", l),
        sub:
          gettext("real GDP %{change} %{since}",
            change: change(changes["real_gdp_index"], "real_gdp_index", l),
            since: since
          ),
        tone: SyliAtlasWeb.Format.tone(at.("real_gdp_growth"), "real_gdp_growth"),
        href: tab.(:economy)
      },
      %{
        id: "gdp-per-capita",
        label: gettext("GDP per capita"),
        value: value(at.("gdp_per_capita_usd"), "gdp_per_capita_usd", l),
        sub: to_string(ctx.to),
        tone: nil,
        href: tab.(:economy)
      },
      %{
        id: "debt",
        label: gettext("Public debt"),
        value: value(at.("public_debt_pct_gdp"), "public_debt_pct_gdp", l),
        sub: gettext("of GDP, %{year}", year: ctx.to),
        tone: nil,
        href: tab.(:finances)
      },
      %{
        id: "population",
        label: gettext("Population"),
        value: value(at.("population_m"), "population_m", l),
        sub: to_string(ctx.to),
        tone: nil,
        href: tab.(:society)
      },
      %{
        id: "rating",
        label: gettext("Rating"),
        value: (rating && rating["label"]) || "—",
        sub:
          if(rating && rating["band"],
            do:
              Enum.join(
                Enum.reject(
                  [
                    SyliAtlasWeb.RatingComponents.verdict(rating["band"]),
                    SyliAtlasWeb.RatingComponents.rank_text(rating, ctx.rated)
                  ],
                  &is_nil/1
                ),
                " · "
              ),
            else: gettext("No agency rating")
          ),
        tone: rating && rating["band"] && "rt-ink-#{rating["band"]}",
        href: tab.(:markets) <> "#notation"
      }
    ]
  end

  attr :area, :map, required: true
  attr :tabs, :list, required: true
  attr :current, :atom, required: true
  attr :locale, :string, required: true
  attr :query, :string, default: "", doc: "the chosen period (?from=&to=), kept from tab to tab"

  def tab_nav(assigns) do
    ~H"""
    <nav class="tab-nav" aria-label={gettext("Sections of this profile")} id="profile-tabs">
      <a
        :for={t <- @tabs}
        href={Paths.area_tab(@locale, @area, t) <> @query}
        aria-current={t == @current && "page"}
        id={"tab-#{t}"}
      >
        {tab_label(t)}
        <span :if={t == @current} class="tab-indicator" aria-hidden="true"></span>
      </a>
    </nav>
    """
  end

  attr :ctx, :map, required: true, doc: "everything the profile knows (see AreaController)"

  @doc "One card per tab, each with its headline figure and two details."
  def overview_cards(assigns) do
    assigns = assign(assigns, :cards, cards(assigns.ctx))

    ~H"""
    <section class="section" id="overview">
      <div class="wrap stack gap-4">
        <div class="overview-grid">
          <a :for={c <- @cards} class="card overview-card" href={c.href} id={"card-#{c.id}"}>
            <p class="eyebrow">{c.title}</p>
            <p class={["big", c.tone]}>{c.value}</p>
            <p class="small muted">{c.caption}</p>
            <dl class="overview-facts">
              <div :for={{label, v} <- c.facts}>
                <dt>{label}</dt>
                <dd class="num">{v}</dd>
              </div>
            </dl>
            <span class="overview-more">
              {gettext("See the details")}<span class="vh"> : {c.title}</span>
              <span aria-hidden="true">→</span>
            </span>
          </a>
        </div>
        <p class="src">{sources_line(@ctx)}</p>
      </div>
    </section>
    """
  end

  defp cards(ctx) do
    l = ctx.locale
    s = ctx.profile["series"]
    to = ctx.to
    ch = ctx.data["period"]["changes"]

    economy = %{
      id: "economy",
      title: tab_label(:economy),
      href: Paths.area_tab(l, ctx.area, :economy) <> ctx.period_query,
      value: change(ch["real_gdp_index"], "real_gdp_index", l),
      tone: SyliAtlasWeb.Format.tone(ch["real_gdp_index"], "real_gdp_index"),
      caption: gettext("real GDP, %{from} → %{to} (IMF)", from: ctx.from, to: to),
      facts: [
        {gettext("Growth %{year}", year: to),
         value(PublicData.at(s["real_gdp_growth"], to), "real_gdp_growth", l)},
        {gettext("GDP %{year}", year: to),
         value(PublicData.at(s["gdp_usd_bn"], to), "gdp_usd_bn", l)}
      ]
    }

    creditors = ctx.world_bank && ctx.world_bank["creditors"]

    finances = %{
      id: "finances",
      title: tab_label(:finances),
      href: Paths.area_tab(l, ctx.area, :finances) <> ctx.period_query,
      value: value(PublicData.at(s["public_debt_pct_gdp"], to), "public_debt_pct_gdp", l),
      tone: nil,
      caption: gettext("public debt, % of GDP, %{year} (IMF)", year: to),
      facts:
        [
          {gettext("Fiscal balance"),
           value(PublicData.at(s["fiscal_balance_pct_gdp"], to), "fiscal_balance_pct_gdp", l)},
          ctx.distress &&
            {gettext("Risk of debt distress"),
             WorldBankComponents.risk_label(ctx.distress["risk"])},
          creditors && {gettext("Owed to China"), pct(creditors["shares"]["china"], l)}
        ]
        |> Enum.filter(& &1)
        |> Enum.take(3)
    }

    trade =
      ctx.trade &&
        %{
          id: "trade",
          title: tab_label(:trade),
          href: Paths.area_tab(l, ctx.area, :trade),
          value: pct(ctx.trade["first_chapter_share"], l),
          tone: nil,
          caption:
            gettext("of exports: %{product}, %{year} (CEPII)",
              product:
                TradeComponents.chapter(ctx.trade_doc, hd(ctx.trade["top_exports"])["chapter"], l),
              year: ctx.trade_doc["year"]
            ),
          facts: [
            {gettext("Exports"), WorldBankComponents.usd(ctx.trade["exports_usd"], l)},
            {gettext("First client"),
             case ctx.trade["top_clients"] do
               [c | _] ->
                 "#{TradeComponents.partner(ctx.trade_doc, c["code"], l)} · #{pct(c["share"], l)}"

               _ ->
                 "—"
             end}
          ]
        }

    latest = (ctx.world_bank && ctx.world_bank["latest"]) || %{}
    society_keys = Enum.filter(~w(electricity poverty accounts unemployment_ilo), &latest[&1])

    society =
      society_keys != [] &&
        (fn ->
           [first | rest] = society_keys

           %{
             id: "society",
             title: tab_label(:society),
             href: Paths.area_tab(l, ctx.area, :society),
             value: pct(latest[first]["value"], l),
             tone: nil,
             caption:
               "#{society_label(first)} · #{latest[first]["year"]} (#{gettext("World Bank")})",
             facts:
               for k <- Enum.take(rest, 2) do
                 {"#{society_label(k)} · #{latest[k]["year"]}", pct(latest[k]["value"], l)}
               end
           }
         end).()

    markets =
      (ctx.rating || ctx.market != [] || ctx.climate) &&
        %{
          id: "markets",
          title: tab_label(:markets),
          href: Paths.area_tab(l, ctx.area, :markets),
          value: (ctx.rating && ctx.rating["label"]) || "—",
          tone: nil,
          caption:
            if(ctx.rating && ctx.rating["band"],
              do: SyliAtlasWeb.RatingComponents.verdict(ctx.rating["band"]),
              else: gettext("No agency rating")
            ),
          facts:
            for x <- Enum.take(ctx.market, 2) do
              {x["exchange"]["short_name"],
               if(x["index"] && x["index"]["value"],
                 do: "#{x["exchange"]["index_name"]} #{x["index"]["value"]}",
                 else: gettext("%{n} listed", n: x["exchange"]["listed"])
               )}
            end
        }

    [economy, finances, trade, society, markets] |> Enum.filter(& &1)
  end

  defp society_label("electricity"), do: gettext("Access to electricity")
  defp society_label("poverty"), do: gettext("Poverty")
  defp society_label("accounts"), do: gettext("Adults with an account")
  defp society_label("unemployment_ilo"), do: gettext("Unemployment")

  defp sources_line(ctx) do
    [
      gettext("IMF, %{label}", label: ctx.profile["edition"]["label"]),
      ctx.world_bank && gettext("World Bank (CC BY 4.0)"),
      ctx.trade && "CEPII, BACI",
      ctx.distress && gettext("IMF debt sustainability analyses"),
      ctx.rating && gettext("rating agencies"),
      ctx.market != [] && SyliAtlas.Market.Catalog.attribution("mansa")
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  attr :ctx, :map, required: true

  @doc """
  « Further reading »: the same tab for countries of the region and of the
  country's communities, the Africa-wide page of the theme, and the
  country's other tabs. Built from the data, so every profile differs.
  """
  def related_links(assigns) do
    assigns = assign(assigns, :groups, related(assigns.ctx))

    ~H"""
    <section :if={@groups != []} class="section section-alt" id="related">
      <div class="wrap stack gap-4">
        <h2 class="h2">{gettext("Further reading")}</h2>
        <div class="related-grid">
          <nav :for={g <- @groups} class="card pad stack gap-2" aria-label={g.title}>
            <p class="eyebrow">{g.title}</p>
            <ul class="related-list">
              <li :for={{label, href} <- g.links}><a href={href}>{label}</a></li>
            </ul>
          </nav>
        </div>
      </div>
    </section>
    """
  end

  defp related(ctx) do
    l = ctx.locale
    tab = ctx.tab
    tab_name = tab_label(if(tab == :overview, do: :economy, else: tab))
    label = fn name -> if tab == :overview, do: name, else: "#{name} · #{tab_name}" end

    region =
      ctx.region_peers
      |> Enum.reject(&(&1["code"] == ctx.area.code))
      |> Enum.take(5)
      |> Enum.map(&{label.(&1["name"]), Paths.country_tab(l, &1["slug"], tab)})

    region_group =
      region != [] &&
        %{title: gettext("In the region: %{region}", region: ctx.region_name), links: region}

    community_groups =
      for c <- Enum.take(ctx.communities, 2),
          links =
            c.members
            |> Enum.reject(&(&1 == ctx.area.code))
            |> Enum.map(&ctx.slugs[&1])
            |> Enum.reject(&is_nil/1)
            |> Enum.take(4)
            |> Enum.map(fn {name, slug} -> {label.(name), Paths.country_tab(l, slug, tab)} end),
          links != [] do
        %{
          title: gettext("In %{community}", community: SyliAtlas.Locales.pick(c.short, l)),
          links:
            links ++
              [
                {gettext("The %{community} page", community: SyliAtlas.Locales.pick(c.short, l)),
                 Paths.community(l, SyliAtlas.Locales.pick(c.slug, l))}
              ]
        }
      end

    theme = %{title: gettext("On this theme, in Africa"), links: theme_links(tab, ctx)}

    pairs =
      for [a, b] = pair <- SyliAtlasWeb.Topics.pairs(), ctx.area.code in pair do
        {other, _} = ctx.slugs[if(a == ctx.area.code, do: b, else: a)] || {nil, nil}
        {gettext("%{a} or %{b}?", a: ctx.name, b: other), SyliAtlasWeb.Topics.pair_path(l, pair)}
      end

    compare_group =
      pairs != [] &&
        %{
          title: gettext("Compare %{name}", name: ctx.name),
          links:
            pairs ++
              [
                {gettext("Other comparisons"),
                 Paths.compare(l, [SyliAtlas.Geo.Area.slug(ctx.area, l)])}
              ]
        }

    others = %{
      title: gettext("%{name}, elsewhere", name: ctx.name),
      links:
        for t <- ctx.tabs, t != tab do
          {tab_label(t), Paths.area_tab(l, ctx.area, t) <> ctx.period_query}
        end ++
          [
            {gettext("All questions on the economy of %{name}", names(ctx.name, [])),
             SyliAtlasWeb.CountryQuestionsController.questions_path(l, ctx.area)}
          ] ++
          if(ctx.rating,
            do: [
              {gettext("Rating history of %{name}", name: ctx.name),
               Paths.rating(l, SyliAtlas.Geo.Area.slug(ctx.area, l))}
            ],
            else: []
          ) ++
          if(pairs == [],
            do: [
              {gettext("Compare %{name}", name: ctx.name),
               Paths.compare(l, [ctx.area |> SyliAtlas.Geo.Area.slug(l)])}
            ],
            else: []
          )
    }

    ([region_group | community_groups] ++ [compare_group, theme, others])
    |> Enum.filter(& &1)
  end

  # Each tab points to the rankings of its theme (SyliAtlasWeb.Topics).
  defp theme_links(tab, ctx) do
    l = ctx.locale
    rank = fn indicator, label -> {label, SyliAtlasWeb.Topics.ranking_path(l, indicator)} end

    case tab do
      :finances ->
        [
          {gettext("Debt of the 54 African countries"), Paths.debt(l)},
          rank.("public_debt_pct_gdp", gettext("Public debt ranking")),
          rank.("fiscal_balance_pct_gdp", gettext("Fiscal balance ranking")),
          rank.("inflation", gettext("Inflation ranking"))
        ]

      :markets ->
        [
          {gettext("Sovereign ratings of the 54 countries"), Paths.ratings(l)},
          {SyliAtlasWeb.Topics.question_text("best_rating"),
           SyliAtlasWeb.Topics.question_path(l, "best_rating")}
        ] ++
          if(SyliAtlas.Market.public?(),
            do: [{gettext("African stock exchanges"), Paths.markets(l)}],
            else: []
          )

      :trade ->
        [
          rank.("current_account_pct_gdp", gettext("Current account ranking")),
          {gettext("Economic communities"), Paths.communities(l)}
        ]

      :society ->
        [
          rank.("population_m", gettext("Population ranking")),
          rank.("unemployment", gettext("Unemployment ranking")),
          rank.("gdp_per_capita_ppp", gettext("GDP per capita in PPP ranking"))
        ]

      _ ->
        [
          rank.("gdp_usd_bn", gettext("GDP ranking")),
          rank.("gdp_per_capita_usd", gettext("GDP per capita ranking")),
          rank.("real_gdp_growth", gettext("Growth ranking")),
          {gettext("Regions of Africa"), Paths.regions(l)}
        ]
    end
  end

  defp pct(nil, _), do: "—"
  defp pct(v, locale), do: number(v, 1, locale) <> " %"

  @doc false
  def communities_of(code), do: Communities.for_country(code)

  attr :area, :any, required: true
  attr :locale, :string, required: true

  @doc "On a region or a continent: the other regions and groupings, and the communities."
  def area_siblings(assigns) do
    others =
      for %{type: :region} = e <- SyliAtlasWeb.Search.Index.get(), e.code != assigns.area.code do
        {SyliAtlas.Locales.pick(e.names, assigns.locale), e.path[assigns.locale], e.kind}
      end
      |> Enum.sort_by(fn {name, _, kind} -> {kind != "region", name} end)

    assigns = assign(assigns, others: others, communities: Communities.all())

    ~H"""
    <section class="section section-alt" id="related">
      <div class="wrap stack gap-4">
        <h2 class="h2">{gettext("Further reading")}</h2>
        <div class="related-grid">
          <nav class="card pad stack gap-2" aria-label={gettext("Other regions and groupings")}>
            <p class="eyebrow">{gettext("Other regions and groupings")}</p>
            <ul class="related-list">
              <li :for={{name, href, _} <- @others}><a href={href}>{name}</a></li>
            </ul>
          </nav>
          <nav class="card pad stack gap-2" aria-label={gettext("Economic communities")}>
            <p class="eyebrow">{gettext("Economic communities")}</p>
            <ul class="related-list">
              <li :for={c <- @communities}>
                <a href={Paths.community(@locale, SyliAtlas.Locales.pick(c.slug, @locale))}>{SyliAtlas.Locales.pick(
                  c.short,
                  @locale
                )} · {c.name[
                  @locale
                ]}</a>
              </li>
            </ul>
          </nav>
        </div>
      </div>
    </section>
    """
  end
end
