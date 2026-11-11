defmodule SyliAtlasWeb.ProfileComponents do
  @moduledoc """
  The frame of a country profile split into tabs: the tab bar, the
  overview (one card per tab, two or three figures each) and the related
  links at the bottom of every tab. Each tab has its own URL
  (`SyliAtlasWeb.Paths.area_tab/3`); a tab without data does not exist.
  """
  use Phoenix.Component
  use Gettext, backend: SyliAtlasWeb.Gettext

  import SyliAtlasWeb.Format, only: [value: 3, change: 3, number: 3]
  alias SyliAtlasWeb.{Paths, PublicData, WorldBankComponents, TradeComponents}
  alias SyliAtlas.Economy.Communities

  def tab_label(:overview), do: gettext("Overview")
  def tab_label(:economy), do: gettext("Economy")
  def tab_label(:finances), do: gettext("Finances and debt")
  def tab_label(:trade), do: gettext("Trade")
  def tab_label(:society), do: gettext("Society")
  def tab_label(:markets), do: gettext("Markets and rating")

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
    suffix = String.replace_prefix(assigns.heading, ctx.name, "") |> String.trim_leading(" · ")

    assigns =
      assign(assigns,
        name: ctx.name,
        area: ctx.area,
        locale: ctx.locale,
        suffix: if(suffix in ["", assigns.heading], do: nil, else: suffix),
        kpis: head_kpis(ctx)
      )

    ~H"""
    <div class="country-head">
      <nav aria-label={gettext("Breadcrumb")}>
        <ol class="crumbs">
          <li><a href={Paths.home(@locale)}>Syli Atlas</a></li>
          <li :if={@region}>
            <a href={Paths.area(@locale, @region)}>{SyliAtlas.Geo.Area.name(@region, @locale)}</a>
          </li>
          <%= if @ctx.tab != :overview do %>
            <li><a href={Paths.area(@locale, @area)}>{@name}</a></li>
            <li aria-current="page">{@tab_name}</li>
          <% else %>
            <li aria-current="page">{@name}</li>
          <% end %>
        </ol>
      </nav>
      <div class="country-id">
        <SyliAtlasWeb.UI.flag code={@area.code} size="lg" />
        <div class="country-id-text">
          <h1 class="country-name">
            {@name}<span :if={@suffix} class="country-name-tab"> · {@suffix}</span>
          </h1>
          <div class="country-chips">
            <a :if={@region} class="pill pill-neutral no-dot" href={Paths.area(@locale, @region)}>
              {SyliAtlas.Geo.Area.name(@region, @locale)}
            </a>
            <a
              :for={c <- @ctx.communities}
              class="pill pill-neutral no-dot"
              href={Paths.community(@locale, c.slug[@locale])}
            >
              {c.short[@locale]}
            </a>
            <a
              :if={@ctx.currency}
              class="pill pill-neutral no-dot"
              href={Paths.area_tab(@locale, @area, :finances) <> @ctx.period_query <> "#monnaie"}
            >
              {@ctx.currency.name} ({@ctx.currency.code})
            </a>
          </div>
        </div>
        <SyliAtlasWeb.AccountComponents.follow
          kind="area"
          ref={@area.code}
          locale={@locale}
          path={@path}
          alert_area={@area.code}
        />
      </div>
      <ul class="card country-kpis" id="country-kpis">
        <li :for={k <- @kpis}>
          <a href={k.href} id={"kpi-#{k.id}"}>
            <span class="country-kpi-label">{k.label}</span>
            <span class={["num country-kpi-value", k.tone]}>{k.value}</span>
            <span class="country-kpi-sub">{k.sub}</span>
          </a>
        </li>
      </ul>
    </div>
    """
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
          title: gettext("In %{community}", community: c.short[l]),
          links:
            links ++
              [
                {gettext("The %{community} page", community: c.short[l]),
                 Paths.community(l, c.slug[l])}
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
        {e.names[assigns.locale], e.path[assigns.locale], e.kind}
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
                <a href={Paths.community(@locale, c.slug[@locale])}>{c.short[@locale]} · {c.name[
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
