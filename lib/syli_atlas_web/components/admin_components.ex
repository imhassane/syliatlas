defmodule SyliAtlasWeb.AdminComponents do
  @moduledoc """
  The frame of the admin pages, as in the mockups: a side bar (logo, menu by
  section with counters, admin session) and the page on a light background.
  """
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: SyliAtlasWeb.Endpoint,
    router: SyliAtlasWeb.Router,
    statics: SyliAtlasWeb.static_paths()

  attr :current, :atom, required: true, doc: ":ratings, :members or :searches"
  attr :counts, :map, default: %{}
  attr :until, :any, default: nil, doc: "when the admin session closes (DateTime)"
  attr :key, :string, default: nil, doc: "name of the passkey used"
  slot :inner_block, required: true

  def admin_shell(assigns) do
    assigns =
      assign(assigns, :sections, [
        {"Données", [{:ratings, "Notations", ~p"/admin/notations", :ratings}]},
        {"Communauté", [{:members, "Membres", ~p"/admin/membres", :members}]},
        {"Site", [{:searches, "Recherches", ~p"/admin/recherches", :searches}]}
      ])

    ~H"""
    <div class="admin" id="admin">
      <aside class="admin-side" id="admin-side">
        <a class="admin-logo" href={~p"/fr"}>
          <svg width="28" height="28" viewBox="0 0 28 28" aria-hidden="true">
            <rect width="13" height="13" rx="3" fill="var(--ink)" />
            <rect x="15" width="13" height="13" rx="3" fill="#4b3bff" />
            <rect y="15" width="13" height="13" rx="3" fill="#4b3bff" />
            <rect x="15" y="15" width="13" height="13" rx="3" fill="#ff6b3d" />
          </svg>
          <span>syli <span>admin</span></span>
        </a>
        <nav aria-label="Administration" class="admin-nav">
          <div :for={{title, links} <- @sections}>
            <h2>{title}</h2>
            <a
              :for={{key, label, href, icon} <- links}
              href={href}
              aria-current={if(key == @current, do: "page")}
              id={"admin-nav-#{key}"}
            >
              <.nav_icon name={icon} />{label}
              <span :if={(@counts[key] || 0) > 0} class="admin-cnt">{@counts[key]}</span>
            </a>
          </div>
        </nav>
        <div class="admin-session" id="admin-session">
          <b>Session admin</b>
          <span class="muted">
            Code + clé{if @key, do: " « #{@key} »"}{if @until,
              do: " · expire à #{Calendar.strftime(@until, "%H h %M")} UTC"}
          </span>
        </div>
      </aside>
      <main id="main" class="admin-main">
        <div>{render_slot(@inner_block)}</div>
      </main>
    </div>
    """
  end

  attr :name, :atom, required: true

  defp nav_icon(%{name: :ratings} = assigns) do
    ~H"""
    <svg
      width="18"
      height="18"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.7"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path d="M4 19V5" /><path d="M4 19h16" /><path d="M8 15l4-4 3 3 5-6" />
    </svg>
    """
  end

  defp nav_icon(%{name: :members} = assigns) do
    ~H"""
    <svg
      width="18"
      height="18"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.7"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <circle cx="9" cy="8" r="3.5" /><path d="M2.5 20a6.5 6.5 0 0 1 13 0" />
    </svg>
    """
  end

  defp nav_icon(%{name: :searches} = assigns) do
    ~H"""
    <svg
      width="18"
      height="18"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.7"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <circle cx="11" cy="11" r="7" /><path d="M20 20l-3.5-3.5" />
    </svg>
    """
  end
end
