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

  attr :current, :atom, required: true, doc: "the menu entry of the page"
  attr :counts, :map, default: %{}
  attr :until, :any, default: nil, doc: "when the admin session closes (DateTime)"
  attr :key, :string, default: nil, doc: "name of the passkey used"
  slot :inner_block, required: true

  def admin_shell(assigns) do
    assigns =
      assign(assigns, :sections, [
        {"Données",
         [
           {:updates, "Mises à jour", ~p"/admin/mises-a-jour", :updates},
           {:ratings, "Notations", ~p"/admin/notations", :ratings},
           {:budgets, "Budgets et lois", ~p"/admin/budgets", :budgets},
           {:market, "Données de marché", ~p"/admin/marches", :market}
         ]},
        {"Communauté",
         [
           {:members, "Membres", ~p"/admin/membres", :members},
           {:emails, "E-mails envoyés", ~p"/admin/emails", :emails}
         ]},
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

  attr :page, SyliAtlasWeb.Pagination, required: true
  attr :path, :string, required: true, doc: "the page's path, without query"
  attr :params, :map, default: %{}, doc: "the current query parameters, kept in the links"
  attr :key, :string, default: "page", doc: "the parameter of this list's page"
  attr :anchor, :string, default: nil
  attr :label, :string, default: "Pages"

  @doc "The site's pager (10 rows a page, `?page=`), in French, with « 11–20 sur 54 »."
  def admin_pager(assigns) do
    ~H"""
    <div :if={@page.pages > 1} class="adm-pager">
      <SyliAtlasWeb.UI.pagination
        page={@page}
        href={&SyliAtlasWeb.Pagination.href(@path, @params, @key, &1, @anchor)}
        label={@label}
        prev_label="Précédente"
        next_label="Suivante"
        summary={"#{@page.offset + 1}–#{@page.offset + length(@page.entries)} sur #{@page.total}"}
      />
    </div>
    """
  end

  attr :tabs, :list, required: true, doc: "[{key, label, href}]"
  attr :current, :string, required: true
  attr :label, :string, default: "Sections"

  @doc "Tabs as links, in a pill bar (the mockups' tablist)."
  def admin_tabs(assigns) do
    ~H"""
    <nav class="adm-tabs" aria-label={@label}>
      <a
        :for={{key, label, href} <- @tabs}
        href={href}
        aria-current={if(key == @current, do: "page")}
        id={"tab-#{key}"}
      >
        {label}
      </a>
    </nav>
    """
  end

  attr :name, :atom, required: true

  defp nav_icon(%{name: :updates} = assigns) do
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
      <path d="M20 12a8 8 0 1 1-2.3-5.7" /><path d="M20 4v5h-5" />
    </svg>
    """
  end

  defp nav_icon(%{name: :market} = assigns) do
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
      <path d="M4 19V5" /><path d="M4 19h16" /><path d="M7 15l3-4 3 2 4-6" />
    </svg>
    """
  end

  defp nav_icon(%{name: :emails} = assigns) do
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
      <rect x="3" y="5" width="18" height="14" rx="2" /><path d="M3 7l9 6 9-6" />
    </svg>
    """
  end

  defp nav_icon(%{name: :budgets} = assigns) do
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
      <path d="M4 10l8-6 8 6" /><path d="M6 10v8M10 10v8M14 10v8M18 10v8" /><path d="M3 20h18" />
    </svg>
    """
  end

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
      <path d="M12 3l2.6 5.6 6 .7-4.5 4.1 1.2 6L12 16.4 6.7 19.4l1.2-6L3.4 9.3l6-.7z" />
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
