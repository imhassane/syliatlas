defmodule SyliAtlasWeb.Plugs.Embed do
  @moduledoc """
  Pipeline of the framed views (`/embed/:locale/…`, SyliAtlasWeb.EmbedController).

    * The language comes from the second segment of the path.
    * The page may be framed by any site: no `X-Frame-Options`, and
      `SyliAtlasWeb.CSP` sends its embed policy (`frame-ancestors *`) instead
      of the site's (`frame-ancestors 'self'`). This pipeline therefore
      skips `put_secure_browser_headers` and sets the other headers itself.
    * No session, no cookie: nothing to consent to on the host's page.
  """
  import Plug.Conn

  alias SyliAtlas.Locales

  def init(opts), do: opts

  def call(%Plug.Conn{path_info: ["embed", locale | _]} = conn, _opts) do
    if Locales.valid?(locale) do
      Gettext.put_locale(SyliAtlasWeb.Gettext, locale)

      conn
      |> assign(:locale, locale)
      |> put_private(:syli_csp, :embed)
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("referrer-policy", "strict-origin-when-cross-origin")
      |> put_resp_header("x-robots-tag", "noindex")
    else
      raise SyliAtlasWeb.NotFoundError
    end
  end

  def call(_conn, _opts), do: raise(SyliAtlasWeb.NotFoundError)
end
