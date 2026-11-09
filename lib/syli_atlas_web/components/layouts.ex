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
        <nav class="nav" aria-label={gettext("Main")}>
          <a href={Paths.home(@locale)} aria-current={@current == :home && "page"}>{gettext("Home")}</a>
          <a href={Paths.ranking(@locale)} aria-current={@current == :ranking && "page"}>{gettext(
            "Countries"
          )}</a>
          <a href={Paths.compare(@locale, [])} aria-current={@current == :compare && "page"}>{gettext(
            "Compare"
          )}</a>
          <a href={Paths.method(@locale)} aria-current={@current == :method && "page"}>{gettext(
            "Method"
          )}</a>
        </nav>
        <div class="header-actions">
          <button type="button" class="btn btn-quiet" data-install>{gettext("Install the app")}</button>
          <a
            :for={{lang, href} <- @alternates}
            :if={lang != @locale and lang in ["fr", "en"]}
            class="btn btn-quiet"
            href={href}
            hreflang={lang}
            lang={lang}
          >
            {String.upcase(lang)}
          </a>
          <button
            type="button"
            class="icon-btn"
            data-theme-toggle
            aria-label={gettext("Switch theme")}
          >
            <svg
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
          </button>
          <a class="btn btn-secondary" href={Paths.login(@locale)}>{gettext("Sign in")}</a>
        </div>
      </div>
    </header>
    <main id="main">
      {render_slot(@inner_block)}
    </main>
    <footer class="site-footer">
      <div class="wrap row between gap-6" style="align-items: flex-start">
        <div class="stack gap-1" style="max-width: 380px">
          <a class="brand" href={Paths.home(@locale)}><b>syli <span>atlas</span></b></a>
          <p class="muted small">
            {gettext("African economies in verifiable figures. Free, open, in French and English.")}
          </p>
        </div>
        <nav aria-label={gettext("Footer")}>
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
