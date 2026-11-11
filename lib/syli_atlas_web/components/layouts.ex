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
        Enum.find(assigns.alternates, fn {l, _} -> l in ["fr", "en"] and l != assigns.locale end)
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
          <.lang_link :if={@other_lang} lang={@other_lang} class="btn btn-quiet hide-mobile" />
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
          <summary aria-current={@current in [:debt, :ratings, :regions, :themes, :method] && "true"}>
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
      }
    ]
  end

  attr :locale, :string, required: true
  attr :other_lang, :any, default: nil

  @top_countries ~w(NGA ZAF EGY DZA ETH MAR KEN CIV)

  @doc """
  Footer: the largest economies, the exchanges, the themes, the data and the
  project, then one line that credits every source with its edition.
  """
  def site_footer(assigns) do
    # From the in-memory search index: no query per page.
    areas =
      for %{type: :country} = e <- SyliAtlasWeb.Search.Index.get(), into: %{}, do: {e.code, e}

    meta = SyliAtlasWeb.Search.Index.meta()

    assigns =
      assigns
      |> assign(:countries, @top_countries |> Enum.map(&areas[&1]) |> Enum.reject(&is_nil/1))
      |> assign(:exchanges, meta.exchanges)
      |> assign(:themes, themes(assigns.locale))
      |> assign(:edition, meta.edition)

    ~H"""
    <footer class="site-footer">
      <div class="wrap footer-grid">
        <div class="stack gap-1 footer-about">
          <a class="brand" href={Paths.home(@locale)}><b>syli <span>atlas</span></b></a>
          <p class="muted small">
            {gettext("African economies in verifiable figures. Free, open, in French and English.")}
          </p>
          <.lang_link :if={@other_lang} lang={@other_lang} class="btn btn-quiet" />
        </div>
        <nav aria-label={gettext("Footer")} class="footer-nav">
          <div class="stack gap-1">
            <b>{gettext("Countries")}</b>
            <a :for={c <- @countries} href={c.path[@locale]}>{c.names[@locale]}</a>
            <a href={SyliAtlasWeb.Topics.ranking_path(@locale, "gdp_usd_bn")}>{gettext(
              "All 54 countries"
            )} →</a>
          </div>
          <div :if={@exchanges != []} class="stack gap-1">
            <b>{gettext("Stock exchanges")}</b>
            <a :for={e <- Enum.take(@exchanges, 7)} href={e.path[@locale]}>{e.short_name}</a>
            <a href={Paths.markets(@locale)}>{gettext("All exchanges")} →</a>
          </div>
          <div class="stack gap-1">
            <b>{gettext("Themes")}</b>
            <a :for={t <- @themes} href={t.href}>{t.label}</a>
            <a href={Paths.communities(@locale)}>{gettext("Economic communities")}</a>
            <a href={Paths.compare(@locale, [])}>{gettext("Compare")}</a>
          </div>
          <div class="stack gap-1" id="footer-rankings">
            <b>{gettext("Rankings")}</b>
            <a
              :for={i <- SyliAtlasWeb.Topics.ranking_indicators()}
              href={SyliAtlasWeb.Topics.ranking_path(@locale, i)}
            >
              {SyliAtlasWeb.PageComponents.indicator_label(i)}
            </a>
            <a href={SyliAtlasWeb.Topics.questions_path(@locale)}>{gettext("Questions")} →</a>
          </div>
          <div class="stack gap-1">
            <b>{gettext("Data")}</b>
            <a href={Paths.about(@locale)}>{gettext("About")}</a>
            <a href={Paths.method(@locale)}>{gettext("Method and sources")}</a>
            <a href={Paths.accessibility(@locale)} id="footer-accessibility">
              {accessibility_mention()}
            </a>
            <a href={Paths.api(@locale)}>{gettext("Public API")}</a>
            <a href="/llms.txt">llms.txt</a>
            <a href="/sitemap.xml">{gettext("Site map")}</a>
          </div>
        </nav>
      </div>
      <div class="wrap footer-credits">
        <p class="small muted">
          {gettext("Sources:")} {gettext("IMF")}<span :if={@edition}> ({@edition})</span>
          · {gettext("World Bank (CC BY 4.0)")} · CEPII, BACI · {gettext(
            "IMF debt sustainability analyses"
          )} · {gettext("rating agencies")}<span :if={@exchanges != []}> · {SyliAtlas.Market.Catalog.attribution("mansa")}</span>.
          <a href={Paths.method(@locale)}>{gettext("Terms of each source")}</a>
        </p>
        <p class="small muted">
          {gettext(
            "Information, not investment advice. Figures are those of the sources; totals and rankings are Syli Atlas calculations."
          )}
          <a href={Paths.method(@locale) <> "#reuse"} rel="license">{gettext(
            "Syli Atlas calculations: CC BY 4.0"
          )}</a>
        </p>
      </div>
    </footer>
    """
  end

  attr :lang, :any, required: true
  attr :class, :string, default: nil

  defp lang_link(assigns) do
    ~H"""
    <a class={@class} href={elem(@lang, 1)} hreflang={elem(@lang, 0)} lang={elem(@lang, 0)}>
      {if elem(@lang, 0) == "en", do: "English", else: "Français"}
    </a>
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
            <.lang_link :if={@other_lang} lang={@other_lang} class="btn btn-secondary" />
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
