defmodule SyliAtlasWeb.EmbedController do
  @moduledoc """
  Figures of Syli Atlas framed by other sites (newspapers, blogs,
  institutions), and the page that writes the code to paste.

    * `frame/2`: `/embed/:locale/:kind/:slug/:view`, the page shown inside
      the `<iframe>`. `view` is an indicator key (a chart, the same as the
      profile's) or `summary` (the key figures). No header, band or tabs;
      source and a link to the profile always at the bottom. Served by the
      `:embed` pipeline (SyliAtlasWeb.Plugs.Embed): its own
      Content-Security-Policy lets any site frame it, the rest of the site
      still refuses to be framed.
    * `builder/2`: `/fr/pays/:slug/integrer`, a public page of the site: a
      GET form (no JavaScript needed) chooses the view, period, theme and
      language, shows the preview and the code.

  Options of a frame: `from`, `to`; `compare=0` (no comparison line);
  `title=0` (the article has its own); `theme=light|dark` (default: the
  reader's setting); `edition` (the IMF edition the code was made with: when
  the site has a newer one, a line says the figures were updated since).
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.{Geo, Locales}
  alias SyliAtlas.Geo.Area
  alias SyliAtlasWeb.Api.Catalog
  alias SyliAtlasWeb.{Charts, Export, NotFoundError, PageComponents, Paths, PublicData, Seo}

  @themes ~w(auto light dark)

  @doc "The views a frame can show, in menu order."
  def views, do: ["summary" | Catalog.indicator_keys()]

  # The frame -------------------------------------------------------------

  def frame(conn, %{"kind" => kind, "slug" => slug, "view" => view} = params) do
    locale = conn.assigns.locale
    area = area!(locale, kind, slug)
    if view not in views(), do: raise(NotFoundError)

    {from, to} = PageComponents.period(params)
    data = PublicData.area(area.code, from, to) || raise NotFoundError
    profile = data["profile"]
    name = Area.name(area, locale)
    opts = options(params)
    base = SyliAtlasWeb.Endpoint.url()
    period = "?from=#{from}&to=#{to}"

    conn
    |> put_root_layout(false)
    |> put_layout(false)
    |> render(:frame,
      locale: locale,
      area: area,
      name: name,
      view: view,
      from: from,
      to: to,
      data: data,
      profile: profile,
      theme: opts.theme,
      show_title: opts.title,
      title: frame_title(view, name, from, to),
      subtitle: subtitle(view, from),
      series: series(view, area, profile, name, from, to, opts.compare, locale),
      kpis: if(view == "summary", do: kpis(data, from, to, locale), else: []),
      updated_from: updated_from(opts.edition, profile["edition"]),
      page_url: base <> Paths.area(locale, area) <> period,
      data_url: base <> Paths.area_data(locale, area, :csv, from, to),
      canonical: base <> Paths.area(locale, area)
    )
  end

  defp area!(locale, kind, slug) do
    area = Geo.get_area_by_slug(slug, locale) || raise NotFoundError

    ok? =
      cond do
        kind == Paths.segment(locale, :country) -> area.kind == "country"
        kind == Paths.segment(locale, :regions) -> area.kind in ["region", "continent"]
        true -> false
      end

    if ok?, do: area, else: raise(NotFoundError)
  end

  defp options(params) do
    %{
      theme: if(params["theme"] in @themes, do: params["theme"], else: "auto"),
      compare: params["compare"] != "0",
      title: params["title"] != "0",
      edition: if(is_binary(params["edition"]), do: String.slice(params["edition"], 0, 20))
    }
  end

  @doc "The title of a view: « Inflation, Côte d'Ivoire, 2015–2030 »."
  def frame_title("summary", name, _from, to),
    do: gettext("%{name}: key figures %{year}", name: name, year: to)

  def frame_title(view, name, _from, _to),
    do:
      gettext("%{indicator}, %{name}, 2015–2030",
        indicator: PageComponents.indicator_label(view),
        name: name
      )

  defp subtitle("summary", _from), do: nil

  defp subtitle("real_gdp_index", from),
    do: gettext("Index, 100 in %{year} · dashed: estimates and projections", year: from)

  defp subtitle(view, _from),
    do:
      gettext("%{unit} · dashed: estimates and projections",
        unit: String.capitalize(Export.unit_label(Catalog.unit(view)), :ascii)
      )

  # The area, and its region (or Africa for a region), as on the profile.
  defp series("summary", _area, _profile, _name, _from, _to, _compare, _locale), do: []

  defp series(view, area, profile, name, from, to, compare?, locale) do
    values = fn series -> prepare(view, series[view] || [], from) end

    own = %{
      id: area.code,
      name: name,
      color: "--c1",
      values: values.(profile["series"]),
      strong: true
    }

    other =
      with true <- compare?,
           %{} = other <- comparison_area(area),
           %{"profile" => p} <- PublicData.area(other.code, from, to) do
        [
          %{
            id: other.code,
            name: Locales.pick(p["name"], locale),
            color: "--c2",
            values: values.(p["series"])
          }
        ]
      else
        _ -> []
      end

    [own | other]
  end

  defp prepare("real_gdp_index", values, from), do: Charts.rebase(values, from)
  defp prepare(_view, values, _from), do: values

  defp comparison_area(%{kind: "country", region_code: code}) when is_binary(code),
    do: Geo.get_area_by_code(code)

  defp comparison_area(%{kind: "region"}), do: Geo.get_area_by_code("africa")
  defp comparison_area(_), do: nil

  # The key figures of the profile's header (country and region alike).
  defp kpis(data, from, to, locale) do
    series = data["profile"]["series"]
    changes = data["period"]["changes"]
    at = fn k -> PublicData.at(series[k], to) end
    since = gettext("since %{year}", year: from)
    value = &SyliAtlasWeb.Format.value/3
    change = &SyliAtlasWeb.Format.change/3

    [
      %{
        label: gettext("GDP %{year}", year: to),
        value: value.(at.("gdp_usd_bn"), "gdp_usd_bn", locale),
        sub: change.(changes["gdp_usd_bn"], "gdp_usd_bn", locale) <> " " <> since,
        tone: nil
      },
      %{
        label: gettext("Growth %{year}", year: to),
        value: value.(at.("real_gdp_growth"), "real_gdp_growth", locale),
        sub:
          gettext("real GDP %{change} %{since}",
            change: change.(changes["real_gdp_index"], "real_gdp_index", locale),
            since: since
          ),
        tone: SyliAtlasWeb.Format.tone(at.("real_gdp_growth"), "real_gdp_growth")
      },
      %{
        label: gettext("GDP per capita"),
        value: value.(at.("gdp_per_capita_usd"), "gdp_per_capita_usd", locale),
        sub: to_string(to),
        tone: nil
      },
      %{
        label: gettext("Inflation"),
        value: value.(at.("inflation"), "inflation", locale),
        sub: to_string(to),
        tone: nil
      },
      %{
        label: gettext("Public debt"),
        value: value.(at.("public_debt_pct_gdp"), "public_debt_pct_gdp", locale),
        sub: gettext("of GDP, %{year}", year: to),
        tone: nil
      },
      %{
        label: gettext("Population"),
        value: value.(at.("population_m"), "population_m", locale),
        sub: to_string(to),
        tone: nil
      }
    ]
  end

  # The edition the code was made with, when the site now has another one.
  defp updated_from(nil, _current), do: nil
  defp updated_from(edition, %{"id" => edition}), do: nil
  defp updated_from(edition, _current), do: edition

  # The page that writes the code ------------------------------------------

  def builder(conn, %{"slug" => slug} = params) do
    locale = conn.assigns.locale
    kind = Paths.segment(locale, if(conn.assigns.kind == :country, do: :country, else: :regions))
    area = area!(locale, kind, slug)
    paths = Locales.each(fn l -> Paths.area_embed(l, area) end)

    if conn.request_path != paths[locale] do
      conn |> put_status(301) |> redirect(to: paths[locale])
    else
      render_builder(conn, params, area, paths)
    end
  end

  defp render_builder(conn, params, area, paths) do
    locale = conn.assigns.locale
    {from, to} = PageComponents.period(params)
    data = PublicData.area(area.code, from, to) || raise NotFoundError
    name = Area.name(area, locale)
    view = if params["view"] in views(), do: params["view"], else: "real_gdp_index"
    embed_locale = if Locales.valid?(params["lang"]), do: params["lang"], else: locale
    opts = options(params)
    edition = data["profile"]["edition"]
    base = SyliAtlasWeb.Endpoint.url()

    query =
      [from: from, to: to, edition: edition["id"]] ++
        if(opts.compare, do: [], else: [compare: 0]) ++
        if(opts.title, do: [], else: [title: 0]) ++
        if(opts.theme == "auto", do: [], else: [theme: opts.theme])

    src = base <> Paths.embed(embed_locale, area, view, query)

    title =
      Gettext.with_locale(SyliAtlasWeb.Gettext, embed_locale, fn ->
        frame_title(view, Area.name(area, embed_locale), from, to) <>
          " (Syli Atlas, " <> gettext("after the IMF") <> ")"
      end)

    height = if view == "summary", do: 320, else: 480

    render(conn, :builder,
      page_title: gettext("Embed the figures of %{name}", SyliAtlasWeb.Format.names(name)),
      seo:
        locale
        |> Seo.page(
          paths,
          gettext(
            "Embed a chart or the key figures of %{name} in an article, free, with the source.",
            SyliAtlasWeb.Format.names(name)
          ),
          %{noindex: true}
        )
        |> Map.delete(:image),
      alternates: Seo.alternates_for_header(paths),
      locale: locale,
      area: area,
      name: name,
      view: view,
      views: Enum.map(views(), &{&1, view_label(&1)}),
      from: from,
      to: to,
      embed_locale: embed_locale,
      opts: opts,
      edition: edition,
      src: src,
      height: height,
      code: iframe_code(src, title, height),
      profile_url: base <> Paths.area(locale, area),
      oembed_url: base <> "/oembed?url=" <> URI.encode_www_form(base <> Paths.area(locale, area))
    )
  end

  @doc "The label of a view in the menu."
  def view_label("summary"), do: gettext("Key figures (6 figures)")

  def view_label(key),
    do: gettext("Chart: %{indicator}", indicator: PageComponents.indicator_label(key))

  @doc "The code to paste: the frame, and the script that sizes it (optional)."
  def iframe_code(src, title, height) do
    origin = SyliAtlasWeb.Endpoint.url()

    ~s(<iframe src="#{html_attr(src)}" title="#{html_attr(title)}" width="100%" height="#{height}" loading="lazy" style="border:0" data-syli-embed></iframe>\n) <>
      ~s(<script async src="#{origin}/embed.js"></script>)
  end

  defp html_attr(text),
    do:
      text
      |> String.replace("&", "&amp;")
      |> String.replace("\"", "&quot;")
      |> String.replace("<", "&lt;")
end
