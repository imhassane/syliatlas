defmodule SyliAtlasWeb.Plugs.Locale do
  @moduledoc "Sets the page language from the URL prefix (/fr or /en)."
  import Plug.Conn

  def init(locale) when locale in ["fr", "en"], do: locale

  def call(conn, locale) do
    Gettext.put_locale(SyliAtlasWeb.Gettext, locale)
    conn |> assign(:locale, locale) |> assign(:public, true)
  end

  @doc "Redirects / to the reader's language."
  def redirect_root(conn, _opts) do
    locale =
      conn
      |> get_req_header("accept-language")
      |> List.first("")
      |> String.downcase()
      |> then(fn h -> if String.starts_with?(h, "en"), do: "en", else: "fr" end)

    conn |> Phoenix.Controller.redirect(to: "/#{locale}") |> halt()
  end
end
