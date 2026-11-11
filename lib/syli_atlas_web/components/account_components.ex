defmodule SyliAtlasWeb.AccountComponents do
  @moduledoc """
  The star and the bell of public pages. Public pages are cached without a
  session, so they render the signed-out version (links to sign-in that
  come back here); `assets/js/ui/account.js` asks `/account/me` and turns
  the star into a toggle for a signed-in member.
  """
  use Phoenix.Component
  use Gettext, backend: SyliAtlasWeb.Gettext

  alias SyliAtlasWeb.Paths

  attr :kind, :string, required: true
  attr :ref, :string, required: true
  attr :locale, :string, required: true
  attr :path, :string, required: true, doc: "this page, to come back after signing in"
  attr :alert_area, :string, default: nil, doc: "country code: shows the bell"

  def follow(assigns) do
    assigns =
      assign(assigns,
        key: assigns.kind <> ":" <> assigns.ref,
        login: Paths.login(assigns.locale) <> "?return_to=" <> URI.encode_www_form(assigns.path)
      )

    ~H"""
    <div class="follow" id="follow">
      <a
        class="btn btn-secondary btn-sm follow-star"
        href={@login}
        id="follow-star"
        data-favorite={@key}
        data-label-on={gettext("Followed")}
        data-label-off={gettext("Follow")}
        aria-pressed="false"
      >
        <svg
          width="18"
          height="18"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="1.8"
          stroke-linejoin="round"
          aria-hidden="true"
        ><path d="M12 3.5l2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.9l-5.2 2.7 1-5.8-4.3-4.1 5.9-.9z"></path></svg>
        <span>{gettext("Follow")}</span>
      </a>
      <a
        :if={@alert_area}
        class="btn btn-quiet btn-sm"
        id="follow-alert"
        href={Paths.account(@locale, :alerts) <> "?area=" <> @alert_area}
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
        ><path d="M6 16V11a6 6 0 1 1 12 0v5l1.5 2h-15z"></path><path d="M10 20.5a2 2 0 0 0 4 0">
        </path></svg>
        <span>{gettext("Create an alert")}</span>
      </a>
    </div>
    """
  end
end
