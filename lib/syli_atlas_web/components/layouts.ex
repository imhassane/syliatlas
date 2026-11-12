defmodule SyliAtlasWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use SyliAtlasWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  alias SyliAtlasWeb.Paths

  @doc """
  Public site layout: offline banner, header, the band (sticky: it stays at
  the top with the filters of the page under it), content, footer. Public pages
  carry no session, so they can be cached by the CDN and the service worker.
  """
  attr :locale, :string, required: true
  attr :current, :atom, default: nil
  attr :alternates, :list, default: []

  attr :ticker, :boolean,
    default: true,
    doc: "the band of indices and ratings under the header (off on account pages)"

  attr :current_user, :any,
    default: nil,
    doc: "set on account pages; public pages ask /account/me"

  slot :inner_block, required: true

  def public(assigns) do
    assigns =
      assign(
        assigns,
        :other_lang,
        if(length(assigns.alternates) > 1, do: assigns.alternates)
      )

    ~H"""
    <a class="skip" href="#main">{gettext("Skip to content")}</a>
    <div class="offline-banner" role="status">
      {gettext("You are offline. Figures shown are the ones saved on this device.")}
    </div>
    <div class="read-progress" aria-hidden="true"></div>
    <header class="site-header">
      <div class="wrap">
        <a class="brand" href={Paths.home(@locale)} aria-label="Syli Atlas">
          <.logo size={28} />
          <b>syli <span>atlas</span></b>
        </a>
        <.main_nav locale={@locale} current={@current} id="header-nav" class="nav nav-desktop" />
        <div :if={@current != :search} class="header-search hide-mobile">
          <SyliAtlasWeb.PageComponents.search_form locale={@locale} id="header-q" compact />
        </div>
        <div class="header-actions">
          <a
            :if={@current != :search}
            class="icon-btn show-mobile"
            href={Paths.search(@locale)}
            aria-label={gettext("Search")}
          >
            <svg
              width="22"
              height="22"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="1.8"
              stroke-linecap="round"
              aria-hidden="true"
            ><circle cx="11" cy="11" r="7"></circle><path d="M20 20l-3.5-3.5"></path></svg>
          </a>
          <button type="button" class="btn btn-quiet hide-mobile" data-install>{gettext(
            "Install the app"
          )}</button>
          <.lang_link
            :if={@other_lang}
            langs={@other_lang}
            locale={@locale}
            id="lang-header"
            class="btn btn-quiet hide-mobile"
          />
          <.theme_button />
          <.account_link
            user={@current_user}
            locale={@locale}
            class="btn btn-secondary hide-mobile"
          />
          <button
            type="button"
            id="drawer-open"
            class="icon-btn show-mobile"
            aria-label={gettext("Menu")}
            aria-expanded="false"
            aria-controls="nav-drawer"
          >
            <svg
              width="22"
              height="22"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="1.8"
              stroke-linecap="round"
              aria-hidden="true"
            ><path d="M4 7h16M4 12h16M4 17h16"></path></svg>
          </button>
        </div>
      </div>
    </header>
    <SyliAtlasWeb.TickerComponents.site_ticker :if={@ticker} locale={@locale} />
    <.nav_drawer
      locale={@locale}
      current={@current}
      other_lang={@other_lang}
      current_user={@current_user}
    />
    <main id="main">
      {render_slot(@inner_block)}
      <%!-- After a table filter or sort, the first paint waits for this mark (root
           layout, « page arrival »), so the rows are there to be measured. --%>
      <span id="vt-ready" hidden></span>
    </main>
    <.site_footer locale={@locale} other_lang={@other_lang} />
    <button
      type="button"
      class="to-top"
      id="to-top"
      aria-label={gettext("Back to top")}
      data-to-top
      hidden
    >
      <svg
        width="18"
        height="18"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
        aria-hidden="true"
      ><path d="M12 19V5M6 11l6-6 6 6"></path></svg>
    </button>
    """
  end

  attr :locale, :string, required: true
  attr :current, :atom, default: nil
  attr :id, :string, required: true
  attr :class, :string, default: "nav"
  attr :flat, :boolean, default: false, doc: "the phone drawer: every link, no menu"

  # Four entries, the exchanges among them while their data may be shown.
  # The themes open a <details> panel (no JavaScript, keyboard-friendly):
  # one line per theme with what it holds and how many countries, then the
  # method. A theme appears once its Africa-wide page exists.
  defp main_nav(assigns) do
    assigns =
      assign(assigns,
        themes: themes(assigns.locale),
        exchanges: length(SyliAtlasWeb.Search.Index.meta().exchanges)
      )

    ~H"""
    <nav id={@id} class={@class} aria-label={gettext("Main")}>
      <%= if @flat do %>
        <a
          href={SyliAtlasWeb.Topics.ranking_path(@locale, "gdp_usd_bn")}
          aria-current={@current in [:ranking, :countries] && "page"}
        >
          <span>{gettext("Countries")}</span><span class="drawer-meta">→</span>
        </a>
        <a
          :if={SyliAtlas.Market.public?()}
          href={Paths.markets(@locale)}
          aria-current={@current == :markets && "page"}
        >
          <span>{gettext("Stock exchanges")}</span>
          <span :if={@exchanges > 0} class="drawer-meta">{ngettext(
            "1 exchange",
            "%{count} exchanges",
            @exchanges
          )}</span>
        </a>
        <p class="drawer-group">{gettext("Themes")}</p>
        <a
          :for={t <- @themes}
          href={t.href}
          aria-current={@current in t.current && "page"}
          class="drawer-sub"
        >
          <span>{t.label}</span><span :if={t.short} class="drawer-meta">{t.short}</span>
        </a>
        <a href={Paths.compare(@locale, [])} aria-current={@current == :compare && "page"}>{gettext(
          "Compare"
        )}</a>
      <% else %>
        <a
          href={SyliAtlasWeb.Topics.ranking_path(@locale, "gdp_usd_bn")}
          aria-current={@current in [:ranking, :countries] && "page"}
        >{gettext("Countries")}</a>
        <a
          :if={SyliAtlas.Market.public?()}
          href={Paths.markets(@locale)}
          aria-current={@current == :markets && "page"}
        >{gettext("Stock exchanges")}</a>
        <details class="nav-menu" data-nav-menu>
          <summary aria-current={
            @current in [:debt, :ratings, :regions, :currencies, :themes, :method] && "true"
          }>
            {gettext("Themes")}
          </summary>
          <div class="nav-menu-pop nav-mega">
            <a
              :for={t <- @themes}
              href={t.href}
              aria-current={@current in t.current && "page"}
              class="nav-mega-item"
            >
              <b>{t.label}</b>
              <span>{t.description}</span>
            </a>
            <div class="nav-mega-foot">
              <p>
                {gettext(
                  "Each theme compares the 54 countries; a country profile has the same theme in a tab."
                )}
              </p>
              <a href={Paths.method(@locale)} aria-current={@current == :method && "page"}>{gettext(
                "Method and sources"
              )} →</a>
            </div>
          </div>
        </details>
        <a href={Paths.compare(@locale, [])} aria-current={@current == :compare && "page"}>{gettext(
          "Compare"
        )}</a>
      <% end %>
    </nav>
    """
  end

  # The themes of the menu, with live counts (both from memory: no query).
  defp themes(locale) do
    rated = (SyliAtlas.Ratings.document() || %{})["rated"]

    [
      %{
        key: :debt,
        current: [:debt],
        label: gettext("Debt"),
        href: Paths.debt(locale),
        description: gettext("Levels, creditors, risk of debt distress · 54 countries"),
        short: gettext("54 countries")
      },
      %{
        key: :ratings,
        current: [:ratings],
        label: gettext("Ratings"),
        href: Paths.ratings(locale),
        description:
          if(rated,
            do: gettext("S&P, Moody's, Fitch · %{n} countries rated", n: rated),
            else: "S&P, Moody's, Fitch"
          ),
        short: rated && gettext("%{n} rated", n: rated)
      },
      %{
        key: :regions,
        current: [:regions, :themes],
        label: gettext("Regions and communities"),
        href: Paths.regions(locale),
        description: gettext("AU regions, ECOWAS, AES, WAEMU, CEMAC, EAC, SADC"),
        short: nil
      },
      %{
        key: :currencies,
        current: [:currencies],
        label: gettext("African currencies"),
        href: Paths.currencies(locale),
        description:
          gettext("Daily rates of the 42 currencies against the dollar, the euro and the yuan"),
        short: gettext("42 currencies")
      }
    ]
  end

  attr :locale, :string, required: true
  attr :other_lang, :any, default: nil

  @top_countries ~w(NGA ZAF EGY DZA ETH MAR KEN CIV)

  @doc """
  Footer (canvas « Syli Atlas — pistes de footer », piste A): the brand and
  the recap card, five columns of links, then the sources, the language and
  the theme. The recap card opens the subscription dialog when JavaScript
  runs (`assets/js/ui/recap.js`); otherwise it leads to the recap page.
  """
  def site_footer(assigns) do
    # From the in-memory search index: no query per page.
    entries = SyliAtlasWeb.Search.Index.get()
    areas = for %{type: :country} = e <- entries, into: %{}, do: {e.code, e}

    meta = SyliAtlasWeb.Search.Index.meta()
    locale = assigns.locale

    assigns =
      assigns
      |> assign(:countries, @top_countries |> Enum.map(&areas[&1]) |> Enum.reject(&is_nil/1))
      |> assign(
        :all_countries,
        areas
        |> Map.values()
        |> Enum.sort_by(&String.normalize(SyliAtlas.Locales.pick(&1.names, locale), :nfd))
      )
      |> assign(:exchanges, meta.exchanges)
      |> assign(:themes, themes(locale))
      |> assign(:rankings, SyliAtlasWeb.Topics.ranking_indicators())
      |> assign(:edition, meta.edition)

    ~H"""
    <footer class="site-footer">
      <div class="footer-sun" aria-hidden="true"></div>
      <div class="wrap footer-top">
        <div class="footer-about">
          <a class="brand" href={Paths.home(@locale)} aria-label="Syli Atlas">
            <.logo size={30} />
            <b>syli <span>atlas</span></b>
          </a>
          <p class="footer-claim">
            {gettext("African economies in verifiable figures. Every figure cites its source.")}
          </p>
        </div>
      </div>
      <div class="wrap">
        <div class="footer-recap" id="footer-recap">
          <form
            class="footer-recap-inner"
            method="get"
            action={Paths.recap(@locale)}
            data-recap-start
            aria-labelledby="footer-recap-title"
          >
            <div class="footer-recap-text">
              <p class="eyebrow">{gettext("The Monday recap")}</p>
              <h2 id="footer-recap-title">
                {gettext(
                  "Ratings, stock exchange, currency and IMF landmarks of your countries, every Monday."
                )}
              </h2>
            </div>
            <div class="footer-recap-form">
              <label class="eyebrow" for="footer-recap-email">{gettext("Email address")}</label>
              <div class="footer-recap-row">
                <input
                  class="input"
                  type="email"
                  name="email"
                  id="footer-recap-email"
                  autocomplete="email"
                  placeholder={gettext("you@example.com")}
                />
                <button class="btn btn-primary btn-lg" type="submit">
                  {gettext("Choose my countries")} →
                </button>
              </div>
              <p class="small muted">
                {gettext(
                  "Without an account. The next step opens the choice of countries, the address already filled in."
                )}
              </p>
            </div>
          </form>
        </div>
      </div>
      <nav aria-label={gettext("Footer")} class="wrap footer-nav">
        <div class="footer-col">
          <h2>{gettext("Countries")}</h2>
          <a :for={c <- @countries} href={c.path[@locale]}>{SyliAtlas.Locales.pick(c.names, @locale)}</a>
          <a class="footer-more" href={SyliAtlasWeb.Topics.ranking_path(@locale, "gdp_usd_bn")}>
            {gettext("All 54 countries")} →
          </a>
        </div>
        <div :if={@exchanges != []} class="footer-col">
          <h2>{gettext("Stock exchanges")}</h2>
          <a :for={e <- Enum.take(@exchanges, 7)} href={e.path[@locale]}>{e.short_name}</a>
          <a class="footer-more" href={Paths.markets(@locale)}>{gettext("All exchanges")} →</a>
        </div>
        <div class="footer-col">
          <h2>{gettext("Explore")}</h2>
          <a :for={t <- @themes} href={t.href}>{t.label}</a>
          <a href={Paths.communities(@locale)}>{gettext("Economic communities")}</a>
          <a href={Paths.compare(@locale, [])}>{gettext("Compare")}</a>
          <a href={SyliAtlasWeb.Topics.questions_path(@locale)}>{gettext("Questions")}</a>
          <a href={SyliAtlasWeb.GlossaryController.index_path(@locale)}>{gettext("Glossary")}</a>
        </div>
        <div class="footer-col" id="footer-rankings">
          <h2>{gettext("Rankings")}</h2>
          <a :for={i <- Enum.take(@rankings, 6)} href={SyliAtlasWeb.Topics.ranking_path(@locale, i)}>
            {SyliAtlasWeb.PageComponents.indicator_label(i)}
          </a>
          <a class="footer-more" href={Paths.ranking(@locale)}>
            {gettext("The %{count} rankings", count: length(@rankings))} →
          </a>
        </div>
        <div class="footer-col">
          <h2>{gettext("The project")}</h2>
          <a href={Paths.about(@locale)}>{gettext("About")}</a>
          <a href={Paths.method(@locale)}>{gettext("Method and sources")}</a>
          <a href={Paths.api(@locale)}>{gettext("Public API")}</a>
          <a href={Paths.accessibility(@locale)} id="footer-accessibility">
            {accessibility_mention()}
          </a>
          <a href="/sitemap.xml">{gettext("Site map")}</a>
          <a href="/llms.txt" class="mono">llms.txt</a>
        </div>
      </nav>
      <div class="footer-bottom">
        <div class="wrap footer-bottom-row">
          <div class="footer-credits">
            <p class="mono">
              {gettext("Sources:")} {gettext("IMF")}<span :if={@edition}> ({@edition})</span>
              · {gettext("World Bank (CC BY 4.0)")} · CEPII, BACI · {gettext(
                "IMF debt sustainability analyses"
              )} · {gettext("rating agencies")}<span :if={@exchanges != []}> · <a
                  href={SyliAtlas.Market.Catalog.url("mansa")}
                  rel="noopener"
                >{SyliAtlas.Market.Catalog.attribution("mansa")}</a></span>.
            </p>
            <p>
              {gettext(
                "Information, not investment advice. Figures are those of the sources; totals and rankings are Syli Atlas calculations."
              )}
              <a href={Paths.method(@locale) <> "#reuse"} rel="license">{gettext(
                "Syli Atlas calculations: CC BY 4.0"
              )}</a>
              · <a href={Paths.method(@locale)}>{gettext("Terms of each source")}</a>
            </p>
          </div>
          <div class="footer-settings">
            <.lang_link
              :if={@other_lang}
              langs={@other_lang}
              locale={@locale}
              id="lang-footer"
              class="btn btn-quiet"
              up
            />
            <.theme_button />
          </div>
        </div>
      </div>
      <.recap_dialog locale={@locale} countries={@countries} all_countries={@all_countries} />
    </footer>
    """
  end

  attr :locale, :string, required: true
  attr :countries, :list, required: true
  attr :all_countries, :list, required: true

  # The recap subscription as a dialog (canvas « Fenêtre Recevoir le récap »).
  # Same form and same endpoint as the recap page; the script posts it as
  # JSON and shows the second step. Closed, it is never painted.
  defp recap_dialog(assigns) do
    ~H"""
    <dialog class="recap-dialog" id="recap-dialog" aria-labelledby="recap-dialog-title">
      <div class="recap-dialog-sun" aria-hidden="true"></div>
      <div class="recap-dialog-body">
        <div class="recap-dialog-head">
          <ol class="auth-steps" aria-label={gettext("Steps")}>
            <li data-recap-step="1" aria-current="step"><span>1</span>{gettext("Your countries")}</li>
            <li data-recap-step="2"><span>2</span>{gettext("Confirmation")}</li>
          </ol>
          <button type="button" class="icon-btn" data-recap-close aria-label={gettext("Close")}>
            <svg
              width="20"
              height="20"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="1.8"
              stroke-linecap="round"
              aria-hidden="true"
            ><path d="M6 6l12 12M18 6L6 18"></path></svg>
          </button>
        </div>

        <form
          method="post"
          action={Paths.recap(@locale)}
          class="stack gap-4"
          id="recap-dialog-form"
          data-recap-form
        >
          <div class="stack gap-1">
            <p class="eyebrow">{gettext("The Monday recap")}</p>
            <h2 class="recap-dialog-title" id="recap-dialog-title">
              {gettext("Your countries, every week, in your inbox")}
            </h2>
            <p class="muted">
              {gettext(
                "For each country: the rating decisions, the stock exchange and the currency of the week, and the IMF landmarks."
              )}
            </p>
          </div>
          <p class="adm-flash err" role="alert" id="recap-dialog-error" hidden></p>
          <label class="field">
            <span class="eyebrow">{gettext("Email address")}</span>
            <input class="input" type="email" name="email" autocomplete="email" required />
          </label>
          <fieldset class="recap-picker">
            <legend>{gettext("Countries of the recap")}</legend>
            <div class="recap-chips" data-recap-chips>
              <label :for={c <- @countries} class="recap-chip">
                <input type="checkbox" name="countries[]" value={c.code} />
                <span><.flag code={c.code} size="sm" sprite />{SyliAtlas.Locales.pick(
                  c.names,
                  @locale
                )}</span>
              </label>
            </div>
            <label class="field recap-add">
              <span class="vh">{gettext("Add a country")}</span>
              <select class="select" data-recap-add>
                <option value="">{gettext("+ Another country")}</option>
                <option
                  :for={c <- @all_countries}
                  value={c.code}
                  data-flag={SyliAtlasWeb.Flags.sprite_href(c.code)}
                >
                  {SyliAtlas.Locales.pick(c.names, @locale)}
                </option>
              </select>
            </label>
          </fieldset>
          <fieldset class="recap-frequency">
            <legend>{gettext("Frequency")}</legend>
            <label class="recap-radio">
              <input type="radio" name="frequency" value="weekly" checked />
              {gettext("Every Monday")}
            </label>
            <label class="recap-radio">
              <input type="radio" name="frequency" value="monthly" />
              {gettext("On the 1st of each month")}
            </label>
          </fieldset>
          <div class="stack gap-1">
            <button class="btn btn-primary btn-lg" type="submit">{gettext("Get the recap")} →</button>
            <p class="small muted center">
              {gettext("Without an account or password. One click in each email to stop.")}
            </p>
          </div>
        </form>

        <div class="stack gap-3" id="recap-dialog-sent" hidden>
          <div class="recap-dialog-icon" aria-hidden="true">
            <svg
              width="24"
              height="24"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="1.8"
              stroke-linecap="round"
              stroke-linejoin="round"
            ><rect x="3" y="5" width="18" height="14" rx="2"></rect><path d="M3 7l9 6 9-6"></path></svg>
          </div>
          <p class="eyebrow">{gettext("Last step")}</p>
          <h2 class="recap-dialog-title" tabindex="-1">{gettext("Confirm in your inbox")}</h2>
          <p class="muted">
            {gettext("We sent a link to")} <b dir="ltr" data-recap-email></b>. {gettext(
              "One click is enough: without it, no recap goes out."
            )}
          </p>
          <div class="recap-dialog-actions">
            <button type="button" class="btn btn-quiet" data-recap-again>{gettext("Change address")}</button>
            <button type="button" class="btn btn-primary" data-recap-close>{gettext("Close")}</button>
          </div>
          <p class="small muted">
            {gettext("Nothing received? Check your spam. The link is valid for 7 days.")}
          </p>
        </div>
      </div>
    </dialog>
    """
  end

  attr :langs, :list, required: true, doc: "[{locale, path}] of this page in every language"
  attr :locale, :string, required: true
  attr :id, :string, required: true
  attr :class, :string, default: nil
  attr :up, :boolean, default: false, doc: "opens above the button (footer, drawer)"

  # The language menu: this page in the other languages, each named in itself.
  defp lang_link(assigns) do
    ~H"""
    <details class={["lang-menu", @up && "lang-menu-up"]} id={@id}>
      <summary class={@class} aria-label={gettext("Language")}>
        <svg
          width="16"
          height="16"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="1.8"
          aria-hidden="true"
        ><circle cx="12" cy="12" r="9"></circle><path d="M3 12h18M12 3c2.5 2.7 3.8 5.7 3.8 9s-1.3 6.3-3.8 9c-2.5-2.7-3.8-5.7-3.8-9S9.5 5.7 12 3z">
        </path></svg>
        <span>{SyliAtlas.Locales.native(@locale)}</span>
      </summary>
      <ul role="list">
        <li :for={{l, href} <- @langs}>
          <a
            href={href}
            hreflang={SyliAtlas.Locales.tag(l)}
            lang={SyliAtlas.Locales.tag(l)}
            dir={SyliAtlas.Locales.dir(l)}
            aria-current={l == @locale && "true"}
          >{SyliAtlas.Locales.native(l)}</a>
        </li>
      </ul>
    </details>
    """
  end

  defp theme_button(assigns) do
    ~H"""
    <button type="button" class="icon-btn" data-theme-toggle aria-label={gettext("Switch theme")}>
      <svg
        class="theme-moon"
        width="18"
        height="18"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="1.8"
        stroke-linecap="round"
        stroke-linejoin="round"
        aria-hidden="true"
      ><path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"></path></svg>
      <svg
        class="theme-sun"
        width="18"
        height="18"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="1.8"
        stroke-linecap="round"
        aria-hidden="true"
      ><circle cx="12" cy="12" r="4"></circle><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4">
      </path></svg>
    </button>
    """
  end

  attr :locale, :string, required: true
  attr :current, :atom, default: nil
  attr :other_lang, :any, default: nil
  attr :current_user, :any, default: nil

  @doc """
  Phone navigation: a drawer from the right edge, swiped closed with the
  finger. A `popover="manual"` holding a horizontal scroll-snap container
  (open and closed stops), so the browser drives the gesture; see
  `assets/js/drawer.js`.
  """
  def nav_drawer(assigns) do
    ~H"""
    <div class="drawer" id="nav-drawer" popover="manual">
      <div class="drawer-scroller">
        <div
          class="drawer-sheet"
          tabindex="-1"
          role="dialog"
          aria-modal="true"
          aria-label={gettext("Menu")}
        >
          <div class="drawer-head">
            <a class="brand" href={Paths.home(@locale)} aria-label="Syli Atlas"><.logo size={28} /><b>syli
            <span>atlas</span></b></a>
            <button
              type="button"
              class="icon-btn"
              data-drawer-close
              aria-label={gettext("Close the menu")}
            >
              <svg
                width="20"
                height="20"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="1.8"
                stroke-linecap="round"
                aria-hidden="true"
              ><path d="M6 6l12 12M18 6L6 18"></path></svg>
            </button>
          </div>
          <SyliAtlasWeb.PageComponents.search_form locale={@locale} id="drawer-q" compact />
          <.main_nav locale={@locale} current={@current} id="drawer-nav" class="drawer-nav" flat />
          <p class="drawer-links small">
            <a href={Paths.method(@locale)}>{gettext("Method and sources")}</a>
            · <a href={Paths.api(@locale)}>{gettext("Open data")}</a>
          </p>
          <div class="drawer-foot stack gap-2">
            <button type="button" class="btn btn-secondary" data-install>{gettext("Install the app")}</button>
            <.lang_link
              :if={@other_lang}
              langs={@other_lang}
              locale={@locale}
              id="lang-drawer"
              class="btn btn-secondary"
              up
            />
            <.account_link user={@current_user} locale={@locale} class="btn btn-primary" />
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :user, :any, required: true
  attr :locale, :string, required: true
  attr :class, :string, required: true

  # "Sign in", or "My space" once signed in. Public pages are cached without
  # a session: assets/js/ui/account.js turns the link into "My space" there.
  defp account_link(assigns) do
    ~H"""
    <a
      :if={@user}
      class={@class}
      href={Paths.account(@user.locale)}
      data-account-link
    >
      {gettext("My space")}
    </a>
    <a
      :if={!@user}
      class={@class}
      href={Paths.login(@locale)}
      data-account-link
      data-space-href={Paths.account(@locale)}
      data-space-label={gettext("My space")}
    >
      {gettext("Sign in")}
    </a>
    """
  end

  @doc "The flash messages (info, error) as the toasts of assets/js/ui/toasts.js expect them."
  def flash_toasts(flash) when is_map(flash) do
    [:info, :error]
    |> Enum.map(&%{kind: &1, message: Phoenix.Flash.get(flash, &1)})
    |> Enum.filter(&(is_binary(&1.message) and &1.message != ""))
  end

  def flash_toasts(_), do: []

  @doc "Texts of the notifications drawn by assets/js (toasts), in the page's language."
  def ui_strings do
    %{
      close: gettext("Close"),
      refresh: gettext("Refresh"),
      later: gettext("Later"),
      update_message: gettext("A new version of Syli Atlas is available"),
      update_description: gettext("Refresh to see it. Nothing you are reading will be lost."),
      data_message: gettext("New IMF figures are online"),
      data_description: gettext("Refresh to see the latest edition."),
      offline_message: gettext("You are offline"),
      offline_description: gettext("Pages you have already opened stay readable."),
      online_message: gettext("Back online"),
      install_message: gettext("Install Syli Atlas"),
      install_description:
        gettext("One tap from your home screen, readable offline, no app store."),
      install_ios: gettext("In Safari, tap Share, then « Add to Home Screen »."),
      install: gettext("Install"),
      not_now: gettext("Not now"),
      installed_message: gettext("Syli Atlas is installed")
    }
  end

  attr :size, :integer, default: 28

  def logo(assigns) do
    ~H"""
    <svg width={@size} height={@size} viewBox="0 0 28 28" aria-hidden="true">
      <rect width="13" height="13" rx="3" fill="var(--ink)" />
      <rect x="15" width="13" height="13" rx="3" fill="#4b3bff" />
      <rect y="15" width="13" height="13" rx="3" fill="#4b3bff" />
      <rect x="15" y="15" width="13" height="13" rx="3" fill="#ff6b3d" />
    </svg>
    """
  end

  @doc "Layout for LiveViews outside the admin (sign-in, discussions)."
  attr :flash, :map, required: true
  attr :locale, :string, default: "fr"
  attr :current_scope, :map, default: nil
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <.public locale={@locale}>
      {render_slot(@inner_block)}
    </.public>
    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <%!-- The flash messages become toasts (FlashToasts hook, assets/js/live.js). --%>
      <div
        id={"#{@id}-toasts"}
        phx-hook="FlashToasts"
        data-flash={Phoenix.json_library().encode!(flash_toasts(@flash))}
        hidden
      >
      </div>

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  # RGAA: the compliance status, on every page, linked to the statement.
  defp accessibility_mention do
    mentions = %{
      full: gettext("Accessibility: fully compliant"),
      partial: gettext("Accessibility: partially compliant"),
      none: gettext("Accessibility: not compliant")
    }

    Map.get(mentions, SyliAtlasWeb.PageController.accessibility_status(), mentions.none)
  end
end
