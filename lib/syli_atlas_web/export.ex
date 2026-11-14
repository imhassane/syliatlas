defmodule SyliAtlasWeb.Export do
  @moduledoc """
  The figures of a country, a region or the continent as a file to
  download: CSV, Excel or JSON (`SyliAtlasWeb.ExportController`).

  Built on the server, in the request, from the area's precomputed document
  (`SyliAtlas.Profiles.Queries.area_profile/3`): no new computation, a few
  kilobytes, cached like the page. Only the IMF series of the profile go
  out; stock prices (MansaAPI: display on the site only) never do, since
  they are not in this document.

  Every file says where its figures come from: the IMF edition, the
  attribution to copy, the licence of Syli Atlas' own calculations, the
  page it was taken from and the export date.

  CSV: one row per indicator, one column per year, then a row of year
  statuses (observed, estimate, projection). In French, Spanish and
  Portuguese, a semicolon and a decimal comma (what Excel expects there);
  elsewhere a comma and a decimal point. `sep=comma|semicolon` overrides it.
  UTF-8 with a byte-order mark, so Excel reads accents right.
  """
  use Gettext, backend: SyliAtlasWeb.Gettext

  alias SyliAtlas.Locales
  alias SyliAtlas.Sources.Indicators
  alias SyliAtlasWeb.Api.{Catalog, V1}
  alias SyliAtlasWeb.{PageComponents, Paths, Seo}

  @doc "The table of an area's IMF figures over `from..to`, ready to write."
  def table(%{"profile" => p}, area, locale, from, to) do
    years = Enum.to_list(from..to)

    years_info = %{
      estimate_from: p["years"]["estimate_from"],
      projection_from: p["years"]["projection_from"]
    }

    rows =
      for key <- Catalog.indicator_keys() do
        values = p["series"][key] || []

        %{
          key: key,
          label: PageComponents.indicator_label(key),
          unit: unit_label(Catalog.unit(key)),
          values: Enum.map(years, &round_value(Enum.at(values, &1 - Indicators.first_year())))
        }
      end

    statuses = Enum.map(years, &status_label(Indicators.status_for(&1, years_info)))
    name = Locales.pick(p["name"], locale)
    source = V1.source(p["edition"])

    %{
      name: name,
      slug: Locales.pick(p["slug"], "en"),
      years: years,
      rows: rows,
      statuses: statuses,
      about: [
        {gettext("Area"), name},
        {gettext("Source"), attribution(source, locale)},
        {gettext("IMF edition"), p["edition"]["label"]},
        {gettext("Licence of the IMF figures"), source.licence_url},
        {gettext("Syli Atlas calculations (real GDP index, regional totals)"),
         "CC BY 4.0 · " <> Seo.license_url()},
        {gettext("Cite"),
         gettext("Syli Atlas, “%{name}”, after IMF, %{edition}",
           name: name,
           edition: p["edition"]["label"]
         )},
        {gettext("Page"), SyliAtlasWeb.Endpoint.url() <> Paths.area(locale, area)},
        {gettext("Exported on"), Date.to_iso8601(Date.utc_today())},
        {gettext("Not included"),
         gettext("stock prices: shown on the site (Data by MansaAPI), not redistributable")}
      ]
    }
  end

  @doc "File name without extension: syli-atlas_cote-d-ivoire_2020-2025."
  def filename(table),
    do: "syli-atlas_#{table.slug}_#{List.first(table.years)}-#{List.last(table.years)}"

  # CSV ------------------------------------------------------------------

  @doc "The separator to use: from `sep`, else the locale's habit."
  def separator("semicolon", _locale), do: ";"
  def separator("comma", _locale), do: ","
  def separator(_, locale), do: if(Locales.base(locale) in ~w(fr es pt), do: ";", else: ",")

  @doc "The CSV text, with its byte-order mark."
  def csv(table, sep) do
    decimal = if sep == ";", do: ",", else: "."

    about =
      Enum.map(table.about, fn {label, value} -> ["# #{label} : #{value}"] end)

    header = [gettext("Indicator"), gettext("Unit") | Enum.map(table.years, &Integer.to_string/1)]
    status = [gettext("Year status"), "" | table.statuses]

    rows =
      Enum.map(table.rows, fn r ->
        [r.label, r.unit | Enum.map(r.values, &csv_number(&1, decimal))]
      end)

    lines = about ++ [header] ++ rows ++ [status]
    "﻿" <> Enum.map_join(lines, "\r\n", &csv_line(&1, sep)) <> "\r\n"
  end

  defp csv_line(cells, sep), do: Enum.map_join(cells, sep, &csv_cell(&1, sep))

  defp csv_cell(nil, _sep), do: ""

  defp csv_cell(text, sep) do
    if String.contains?(text, [sep, "\"", "\n", "\r"]) or String.starts_with?(text, "#"),
      do: "\"" <> String.replace(text, "\"", "\"\"") <> "\"",
      else: text
  end

  defp csv_number(nil, _decimal), do: nil
  defp csv_number(n, "."), do: number_text(n)
  defp csv_number(n, ","), do: n |> number_text() |> String.replace(".", ",")

  defp number_text(n) when is_integer(n), do: Integer.to_string(n)
  defp number_text(n), do: :erlang.float_to_binary(n, [:short])

  # Excel ----------------------------------------------------------------

  @doc "The Excel file's bytes: a sheet of figures, a sheet of sources."
  def xlsx(table) do
    header = [gettext("Indicator"), gettext("Unit") | table.years]
    rows = Enum.map(table.rows, fn r -> [r.label, r.unit | r.values] end)
    status = [gettext("Year status"), nil | table.statuses]
    year_widths = Enum.map(table.years, fn _ -> 10 end)

    SyliAtlasWeb.Export.Xlsx.build([
      {gettext("Data"), [header | rows] ++ [status], [34, 30 | year_widths]},
      {gettext("About"),
       [[gettext("Item"), gettext("Value")] | Enum.map(table.about, &Tuple.to_list/1)], [40, 110]}
    ])
  end

  # Pieces ---------------------------------------------------------------

  defp round_value(v) when is_float(v), do: Float.round(v, 2)
  defp round_value(v), do: v

  # The attribution of the API, without its « Source : » (the row says it).
  defp attribution(source, locale) do
    text = if Locales.base(locale) == "fr", do: source.attribution.fr, else: source.attribution.en
    text |> String.replace_prefix("Source : ", "") |> String.replace_prefix("Source: ", "")
  end

  defp status_label("actual"), do: gettext("observed")
  defp status_label("estimate"), do: gettext("estimate")
  defp status_label("projection"), do: gettext("projection")

  @doc "The unit of an indicator's values, in the current language."
  def unit_label("percent"), do: "%"
  def unit_label("percent_of_gdp"), do: gettext("% of GDP")
  def unit_label("percent_of_labour_force"), do: gettext("% of the labour force")
  def unit_label("usd_billion"), do: gettext("billions of current US dollars")
  def unit_label("usd"), do: gettext("current US dollars")
  def unit_label("intl_dollar"), do: gettext("current international dollars (PPP)")
  def unit_label("million_people"), do: gettext("millions of people")
  def unit_label("index_2015"), do: gettext("index, 100 in 2015")
  def unit_label(other), do: other
end
