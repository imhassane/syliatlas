defmodule SyliAtlasWeb.TradeExportController do
  @moduledoc """
  A country's Trade tab as files, from the same figures as the page
  (SyliAtlas.Trade, CEPII BACI): `/fr/pays/cote-d-ivoire/commerce/produits.csv`,
  `…/clients.csv`, `…/afrique.csv`, `…/historique.csv`, `…/potentiel.csv`,
  and all of them in one archive, `…/tout.zip`.

  Each file starts with lines of context (`# Source : …`), uses the
  separator the language expects (`;` and a decimal comma in French,
  Spanish and Portuguese, `,` elsewhere; `?sep=comma|semicolon` to choose)
  and a byte-order mark, so Excel opens it with its accents.
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.{Geo, Trade}
  alias SyliAtlas.Geo.Area
  alias SyliAtlasWeb.{Export, NotFoundError, Paths, TradeComponents, TradeRankingController}

  @files ~w(products clients africa history potential)

  @names %{
    "fr" => %{
      "products" => "produits",
      "clients" => "clients",
      "africa" => "afrique",
      "history" => "historique",
      "potential" => "potentiel",
      "all" => "tout"
    },
    "en" => %{
      "products" => "products",
      "clients" => "clients",
      "africa" => "africa",
      "history" => "history",
      "potential" => "potential",
      "all" => "all"
    },
    "es" => %{
      "products" => "productos",
      "clients" => "clientes",
      "africa" => "africa",
      "history" => "historico",
      "potential" => "potencial",
      "all" => "todo"
    },
    "pt" => %{
      "products" => "produtos",
      "clients" => "clientes",
      "africa" => "africa",
      "history" => "historico",
      "potential" => "potencial",
      "all" => "tudo"
    }
  }

  @doc "The files, in menu order."
  def files, do: @files

  @doc "Address of one file of a country's Trade tab (`:all` for the archive)."
  def path(locale, area, file) do
    name = @names[SyliAtlas.Locales.base(locale)][file]
    ext = if file == "all", do: "zip", else: "csv"
    Paths.area_tab(locale, area, :trade) <> "/#{name}.#{ext}"
  end

  def show(conn, %{"slug" => slug, "file" => file} = params) do
    locale = conn.assigns.locale
    area = Geo.get_area_by_slug(slug, locale) || raise NotFoundError
    if area.kind != "country", do: raise(NotFoundError)
    entry = Trade.for_country(area.code) || raise NotFoundError
    doc = Trade.document()
    names = @names[SyliAtlas.Locales.base(locale)]
    sep = Export.separator(params["sep"], locale)
    name = Area.name(area, locale)
    slug_in = Area.slug(area, locale)

    case Enum.find(Map.keys(names), &(file in ["#{names[&1]}.csv", "#{names[&1]}.zip"])) do
      "all" ->
        entries =
          for f <- @files do
            {String.to_charlist("syli-atlas_#{slug_in}_#{names[f]}_#{doc["year"]}.csv"),
             csv(f, entry, doc, area, name, locale, sep)}
          end

        {:ok, {_, zip}} = :zip.create(~c"trade.zip", entries, [:memory])

        conn
        |> put_resp_content_type("application/zip", nil)
        |> put_resp_header(
          "content-disposition",
          ~s(attachment; filename="syli-atlas_#{slug_in}_#{names["all"]}_#{doc["year"]}.zip")
        )
        |> put_resp_header("x-robots-tag", "noindex")
        |> send_resp(200, zip)

      f when f in @files ->
        if not String.ends_with?(file, ".csv"), do: raise(NotFoundError)

        TradeRankingController.send_csv(
          conn,
          "syli-atlas_#{slug_in}_#{names[f]}_#{doc["year"]}.csv",
          csv(f, entry, doc, area, name, locale, sep)
        )

      _ ->
        raise NotFoundError
    end
  end

  @doc "Title of a file (menu and first line)."
  def title("products"), do: gettext("Products and their buyers")
  def title("clients"), do: gettext("Clients and suppliers")
  def title("africa"), do: gettext("Trade with each African country")
  def title("history"), do: gettext("Exports since 1995")
  def title("potential"), do: gettext("African potential")

  def hint("products"), do: gettext("HS 4-digit headings, share and 5 buyers each")
  def hint("clients"), do: gettext("the main partners, with their share")
  def hint("africa"), do: gettext("exports and imports, country by country")
  def hint("history"), do: gettext("one row per year, in dollars")
  def hint("potential"), do: gettext("products bought outside Africa that Africa exports")

  defp csv(file, e, doc, area, name, locale, sep) do
    {header, rows} = table(file, e, doc, locale)

    Export.csv_document(
      TradeRankingController.about(
        doc,
        "#{title(file)} · #{name}",
        Paths.area_tab(locale, area, :trade)
      ),
      header,
      rows,
      sep
    )
  end

  defp partner(doc, code, locale), do: TradeComponents.partner(doc, code, locale)

  defp table("products", e, doc, locale) do
    {[
       gettext("HS code"),
       gettext("Product"),
       gettext("Exports (US dollars)"),
       gettext("Share of exports (%)"),
       gettext("Buyers (share of the product, %)")
     ],
     for p <- e["top_products"] || [] do
       [
         p["code"],
         Trade.heading(doc, p["code"], locale),
         p["value"],
         p["share"],
         Enum.map_join(p["clients"], ", ", &"#{partner(doc, &1["code"], locale)} #{&1["share"]}")
       ]
     end}
  end

  defp table("clients", e, doc, locale) do
    rows = fn list, label ->
      for r <- list || [],
          do: [label, partner(doc, r["code"], locale), r["code"], r["value"], r["share"]]
    end

    {[
       gettext("Table"),
       gettext("Partner"),
       gettext("ISO code"),
       gettext("Value (US dollars)"),
       gettext("Share (%)")
     ],
     rows.(e["top_clients"], gettext("Client")) ++ rows.(e["top_suppliers"], gettext("Supplier"))}
  end

  defp table("africa", e, doc, locale) do
    names = Map.new(Geo.list_countries(), &{&1.code, Area.name(&1, locale)})

    {[
       gettext("Country"),
       gettext("ISO code"),
       gettext("Exports to it (US dollars)"),
       gettext("Imports from it (US dollars)")
     ],
     for {code, [ex, im]} <-
           Enum.sort_by(e["africa_trade"] || %{}, fn {_, [x, i]} -> -(x + i) end) do
       [names[code] || partner(doc, code, locale), code, ex, im]
     end}
  end

  defp table("history", e, _doc, _locale) do
    shares = get_in(e, ["history", "first_chapter_share"]) || %{}

    {[
       gettext("Year"),
       gettext("Exports of goods (US dollars)"),
       gettext("Share of the first chapter (%)")
     ], for({y, v} <- Trade.history(e), do: [to_string(y), v, shares[to_string(y)]])}
  end

  defp table("potential", e, doc, locale) do
    {[
       gettext("HS code"),
       gettext("Product"),
       gettext("Imports from outside Africa (US dollars)"),
       gettext("Main supplier"),
       gettext("African exporters")
     ],
     for p <- e["potential"] || [] do
       [
         p["code"],
         Trade.heading(doc, p["code"], locale),
         p["value"],
         partner(doc, p["supplier"], locale),
         Enum.map_join(p["exporters"], ", ", &partner(doc, &1, locale))
       ]
     end}
  end
end
