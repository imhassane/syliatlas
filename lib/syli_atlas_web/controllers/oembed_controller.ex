defmodule SyliAtlasWeb.OembedController do
  @moduledoc """
  oEmbed (https://oembed.com): WordPress, Ghost and other publishing tools
  turn a pasted address of Syli Atlas into its embed by themselves.

  `GET /oembed?url=…` takes the address of a country or region profile
  (any tab, any language: the key figures), or of a frame (`/embed/…`: that
  very view), and answers a `rich` type in JSON. Profiles announce it with
  a `<link rel="alternate" type="application/json+oembed">`.
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.{Geo, Locales}
  alias SyliAtlasWeb.{EmbedController, Paths}

  @max_width 1200

  def show(conn, %{"url" => url} = params) do
    cond do
      params["format"] not in [nil, "json"] ->
        conn |> put_status(501) |> json(%{error: "only format=json is served"})

      found = resolve(url) ->
        send_oembed(conn, found, params)

      true ->
        conn |> put_status(404) |> json(%{error: "not an embeddable Syli Atlas address"})
    end
  end

  def show(conn, _params), do: conn |> put_status(400) |> json(%{error: "url is required"})

  defp send_oembed(conn, {locale, area, view, query}, params) do
    base = SyliAtlasWeb.Endpoint.url()
    src = base <> Paths.embed(locale, area, view, query)
    height = if view == "summary", do: 320, else: 480
    width = min(int(params["maxwidth"]) || 640, @max_width)
    height = min(height, int(params["maxheight"]) || height)

    {from, to} = SyliAtlasWeb.PageComponents.period(Map.new(query))

    title =
      Gettext.with_locale(SyliAtlasWeb.Gettext, locale, fn ->
        EmbedController.frame_title(view, Geo.Area.name(area, locale), from, to)
      end)

    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("cache-control", "public, max-age=86400")
    |> json(%{
      version: "1.0",
      type: "rich",
      provider_name: "Syli Atlas",
      provider_url: base,
      title: title,
      html: EmbedController.iframe_code(src, title, height),
      width: width,
      height: height,
      cache_age: 86_400
    })
  end

  # The locale, area, view and query of an address of the site, or nil.
  defp resolve(url) when is_binary(url) do
    uri = URI.parse(url)

    with true <- same_site?(uri),
         {:ok, locale, rest} <- split(uri.path) do
      query =
        uri.query
        |> Kernel.||("")
        |> URI.decode_query()
        |> Map.take(~w(from to theme compare title edition))

      area_view(locale, rest, query)
    else
      _ -> nil
    end
  end

  defp resolve(_url), do: nil

  # The site's own host (or a path alone, for tests and previews).
  defp same_site?(%URI{host: nil}), do: true
  defp same_site?(%URI{host: host}), do: host == SyliAtlasWeb.Endpoint.host()

  defp split(path) when is_binary(path) do
    case String.split(path, "/", trim: true) do
      ["embed", locale | rest] ->
        if Locales.valid?(locale), do: {:ok, locale, {:frame, rest}}, else: :error

      [locale | rest] ->
        if Locales.valid?(locale), do: {:ok, locale, {:page, rest}}, else: :error

      _ ->
        :error
    end
  end

  defp split(_), do: :error

  defp area_view(locale, {:frame, [kind, slug, view]}, query) do
    with %{} = area <- area(locale, kind, slug), true <- view in EmbedController.views() do
      {locale, area, view, Enum.to_list(query)}
    else
      _ -> nil
    end
  end

  defp area_view(locale, {:page, [kind, slug | _tab]}, query) do
    case area(locale, kind, slug) do
      nil -> nil
      area -> {locale, area, "summary", query |> Map.take(~w(from to)) |> Enum.to_list()}
    end
  end

  defp area_view(_locale, _rest, _query), do: nil

  defp area(locale, kind, slug) do
    area = Geo.get_area_by_slug(slug, locale)

    cond do
      is_nil(area) -> nil
      kind == Paths.segment(locale, :country) and area.kind == "country" -> area
      kind == Paths.segment(locale, :regions) and area.kind in ["region", "continent"] -> area
      true -> nil
    end
  end

  defp int(nil), do: nil

  defp int(text) do
    case Integer.parse(to_string(text)) do
      {n, ""} when n > 0 -> n
      _ -> nil
    end
  end
end
