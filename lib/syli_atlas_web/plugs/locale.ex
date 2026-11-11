defmodule SyliAtlasWeb.Plugs.Locale do
  @moduledoc """
  Sets the page language from the URL prefix (/fr, /en, /es…), and sends
  the bare address `/` to the reader's language.
  """
  import Plug.Conn

  alias SyliAtlas.Locales

  def init(:from_path), do: :from_path
  def init(locale), do: if(Locales.valid?(locale), do: locale, else: raise(ArgumentError))

  def call(%Plug.Conn{path_info: [locale | _]} = conn, :from_path), do: call(conn, locale)

  def call(conn, locale) do
    Gettext.put_locale(SyliAtlasWeb.Gettext, locale)
    conn |> assign(:locale, locale) |> assign(:public, true)
  end

  @doc """
  Redirects / to the reader's language: the first language of their
  browser that the site has, unless it is English (the default of many
  browsers, in Dakar as in Abidjan); then the language of their country
  (Cloudflare's CF-IPCountry header); then English.
  """
  def redirect_root(conn, _opts) do
    locale = reader_locale(conn)

    conn
    |> put_resp_header("vary", "Accept-Language, CF-IPCountry")
    |> put_resp_header("cache-control", "private, no-store")
    |> Phoenix.Controller.redirect(to: "/#{locale}")
    |> halt()
  end

  def reader_locale(conn) do
    header = fn name -> conn |> get_req_header(name) |> List.first() end

    case Locales.from_accept_language(header.("accept-language")) do
      locale when locale not in [nil, "en"] -> locale
      browser -> Locales.for_country(header.("cf-ipcountry")) || browser || Locales.default()
    end
  end
end
