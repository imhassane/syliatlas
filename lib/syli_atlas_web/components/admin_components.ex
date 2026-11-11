defmodule SyliAtlasWeb.AdminComponents do
  @moduledoc "Pieces shared by the admin pages: the header with the brand and the admin menu."
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: SyliAtlasWeb.Endpoint,
    router: SyliAtlasWeb.Router,
    statics: SyliAtlasWeb.static_paths()

  attr :current, :atom, required: true, doc: ":ratings, :members or :searches"

  @doc "The admin header: « syli atlas · admin » and the menu of the admin pages."
  def admin_bar(assigns) do
    assigns =
      assign(assigns, :links, [
        {:ratings, "Notations", ~p"/admin/notations"},
        {:members, "Membres", ~p"/admin/membres"},
        {:searches, "Recherches", ~p"/admin/recherches"}
      ])

    ~H"""
    <header class="adm-bar" id="adm-bar">
      <div class="wrap">
        <a class="adm-brand" href={~p"/fr"}>
          syli <span>atlas</span> <span class="mono subtle">· admin</span>
        </a>
        <nav class="nav" aria-label="Admin">
          <a
            :for={{key, label, href} <- @links}
            href={href}
            aria-current={if(key == @current, do: "page")}
          >
            {label}
          </a>
        </nav>
      </div>
    </header>
    """
  end
end
