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
  Public site layout: header, offline banner, content, footer. Public pages
  carry no session, so they can be cached by the CDN and the service worker.
  """
  attr :locale, :string, required: true
  attr :current, :atom, default: nil
  attr :alternates, :list, default: []
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
    <header class="site-header">
      <div class="wrap">
        <a class="brand" href={Paths.home(@locale)} aria-label="Syli Atlas">
          <.logo size={28} />
          <b>syli <span>atlas</span></b>
        </a>
        <.main_nav locale={@locale} current={@current} id="header-nav" class="nav nav-desktop" />
        <div class="header-actions">
          <button type="button" class="btn btn-quiet hide-mobile" data-install>{gettext(
            "Install the app"
          )}</button>
          <.lang_link :if={@other_lang} lang={@other_lang} class="btn btn-quiet hide-mobile" />
          <.theme_button />
          <a class="btn btn-secondary hide-mobile" href={Paths.login(@locale)}>{gettext("Sign in")}</a>
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
    <.nav_drawer locale={@locale} current={@current} other_lang={@other_lang} />
    <main id="main">
      {render_slot(@inner_block)}
    </main>
    <footer class="site-footer">
      <div class="wrap footer-grid">
        <div class="stack gap-1 footer-about">
          <a class="brand" href={Paths.home(@locale)}><b>syli <span>atlas</span></b></a>
          <p class="muted small">
            {gettext("African economies in verifiable figures. Free, open, in French and English.")}
          </p>
        </div>
        <nav aria-label={gettext("Footer")} class="footer-nav">
          <div class="stack gap-1">
            <b>{gettext("Explore")}</b>
            <a href={Paths.ranking(@locale)}>{gettext("All countries")}</a>
            <a href={Paths.compare(@locale, [])}>{gettext("Compare")}</a>
          </div>
          <div class="stack gap-1">
            <b>{gettext("Data")}</b>
            <a href="/api/v1/areas">{gettext("Public API")}</a>
            <a href={Paths.method(@locale)}>{gettext("Method and sources")}</a>
          </div>
        </nav>
      </div>
    </footer>
    """
  end

  attr :locale, :string, required: true
  attr :current, :atom, default: nil
  attr :id, :string, required: true
  attr :class, :string, default: "nav"

  defp main_nav(assigns) do
    ~H"""
    <nav id={@id} class={@class} aria-label={gettext("Main")}>
      <a href={Paths.home(@locale)} aria-current={@current == :home && "page"}>{gettext("Home")}</a>
      <a href={Paths.ranking(@locale)} aria-current={@current == :ranking && "page"}>{gettext(
        "Countries"
      )}</a>
      <a href={Paths.regions(@locale)} aria-current={@current == :regions && "page"}>{gettext(
        "Regions"
      )}</a>
      <a href={Paths.compare(@locale, [])} aria-current={@current == :compare && "page"}>{gettext(
        "Compare"
      )}</a>
      <a
        :if={SyliAtlas.Market.public?()}
        href={Paths.markets(@locale)}
        aria-current={@current == :markets && "page"}
      >{gettext("Stock exchanges")}</a>
      <a href={Paths.ratings(@locale)} aria-current={@current == :ratings && "page"}>{gettext(
        "Ratings"
      )}</a>
      <a href={Paths.method(@locale)} aria-current={@current == :method && "page"}>{gettext("Method")}</a>
    </nav>
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
          <.main_nav locale={@locale} current={@current} id="drawer-nav" class="drawer-nav" />
          <div class="drawer-foot stack gap-2">
            <button type="button" class="btn btn-secondary" data-install>{gettext("Install the app")}</button>
            <.lang_link :if={@other_lang} lang={@other_lang} class="btn btn-secondary" />
            <a class="btn btn-primary" href={Paths.login(@locale)}>{gettext("Sign in")}</a>
          </div>
        </div>
      </div>
    </div>
    """
  end

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
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

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
end
