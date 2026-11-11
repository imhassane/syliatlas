defmodule SyliAtlasWeb.ApiDoc do
  @moduledoc """
  The content of the API page (`/fr/api`, `/en/api`): routes, parameters,
  code in four languages and real answers, shortened. Examples are built
  from the data online and kept in memory until the data changes.
  """
  alias SyliAtlas.Profiles
  alias SyliAtlas.Profiles.Queries
  alias SyliAtlasWeb.CodeHighlight

  @doc "The routes of the page, in order, with their examples in `locale`."
  def routes(locale) do
    base = SyliAtlasWeb.Endpoint.url() <> "/api/v1"
    examples = examples()

    for r <- specs(locale) do
      url = base <> r.example_path

      r
      |> Map.put(:url, url)
      |> Map.put(:code, code(r, url, base))
      |> Map.put(:response, CodeHighlight.lines(examples[r.id] || "", r.format))
    end
  end

  @doc "A short example of an error answer, coloured."
  def error_example(locale) do
    anchor = if locale == "fr", do: "erreurs", else: "errors"

    """
    {
      "error": {
        "code": "unknown_area",
        "message": "Unknown area: XXX",
        "docs": "#{SyliAtlasWeb.Endpoint.url()}/#{locale}/api##{anchor}"
      }
    }\
    """
    |> CodeHighlight.lines(:json)
  end

  # Routes ------------------------------------------------------------

  defp specs(locale) do
    period = [
      param(
        "from",
        "integer",
        "query",
        false,
        "2015 – 2030",
        "2020",
        t(locale, "Année de départ de la période.", "First year of the period.")
      ),
      param(
        "to",
        "integer",
        "query",
        false,
        "2015 – 2030",
        "2025",
        t(locale, "Année d'arrivée, après from.", "Last year, after from.")
      )
    ]

    code =
      param(
        "code",
        "string",
        "path",
        true,
        "CIV, SEN, west_africa…",
        "—",
        t(
          locale,
          "Code ISO 3 du pays, ou code de région.",
          "ISO 3 code of the country, or region code."
        )
      )

    [
      %{
        id: "areas",
        path: "/api/v1/areas",
        example_path: "/areas",
        format: :json,
        desc:
          t(
            locale,
            "Toutes les zones : 54 pays, 5 régions de l'Union africaine, l'Afrique et 2 agrégats du FMI, avec leurs noms en français et en anglais.",
            "Every area: 54 countries, the 5 African Union regions, Africa and 2 IMF aggregates, with their names in French and English."
          ),
        params: [],
        ok: t(locale, "Liste des zones", "List of areas"),
        errors: []
      },
      %{
        id: "area",
        path: "/api/v1/areas/{code}",
        example_path: "/areas/CIV?from=2020&to=2025",
        format: :json,
        desc:
          t(
            locale,
            "Toutes les séries d'une zone, année par année de 2015 à 2030, avec son rang en Afrique et dans sa région sur la période choisie. Après 2024 : estimations puis projections du FMI.",
            "Every series of an area, year by year from 2015 to 2030, with its rank in Africa and in its region over the chosen period. After 2024: IMF estimates, then projections."
          ),
        params: [code | period],
        ok: t(locale, "Fiche de la zone", "Profile of the area"),
        errors: [
          {"400", "invalid_period",
           t(
             locale,
             "années hors 2015–2030, ou from ≥ to",
             "years outside 2015–2030, or from ≥ to"
           )},
          {"404", "unknown_area", t(locale, "code de zone inconnu", "unknown area code")}
        ]
      },
      %{
        id: "compare",
        path: "/api/v1/compare",
        example_path: "/compare?codes=CIV,GHA",
        format: :json,
        desc:
          t(
            locale,
            "Les séries de 2 à 6 zones dans une seule réponse, dans l'ordre demandé. Les codes inconnus sont ignorés.",
            "The series of 2 to 6 areas in one answer, in the order asked. Unknown codes are left out."
          ),
        params: [
          param(
            "codes",
            "string",
            "query",
            true,
            "CIV,GHA,SEN",
            "—",
            t(
              locale,
              "Codes séparés par des virgules, 6 au plus.",
              "Codes separated by commas, 6 at most."
            )
          )
          | period
        ],
        ok: t(locale, "Séries des zones demandées", "Series of the areas asked"),
        errors: [
          {"400", "codes_required", t(locale, "aucun code fourni", "no code given")},
          {"400", "invalid_period", t(locale, "période impossible", "impossible period")}
        ]
      },
      %{
        id: "ranking",
        path: "/api/v1/ranking",
        example_path: "/ranking?indicator=real_gdp_index",
        format: :json,
        desc:
          t(
            locale,
            "Les pays classés selon un indicateur : progression sur la période (par défaut) ou valeur de l'année d'arrivée.",
            "Countries ranked on an indicator: change over the period (by default) or value in the last year."
          ),
        params:
          [
            param(
              "indicator",
              "string",
              "query",
              false,
              "real_gdp_index, inflation, public_debt_pct_gdp…",
              "real_gdp_index",
              t(locale, "Indicateur à classer.", "Indicator to rank.")
            ),
            param(
              "mode",
              "enum",
              "query",
              false,
              "change | value",
              "change",
              t(locale, "Progression ou valeur.", "Change or value.")
            ),
            param(
              "region",
              "string",
              "query",
              false,
              "west_africa, east_africa…",
              t(locale, "toutes", "all"),
              t(locale, "Limiter à une région.", "Keep one region.")
            ),
            param(
              "locale",
              "enum",
              "query",
              false,
              "fr | en",
              "fr",
              t(locale, "Langue des noms.", "Language of the names.")
            )
          ] ++ period,
        ok: t(locale, "Pays classés", "Ranked countries"),
        errors: [
          {"400", "unknown_indicator", t(locale, "indicateur inconnu", "unknown indicator")},
          {"400", "invalid_period", t(locale, "période impossible", "impossible period")}
        ]
      },
      %{
        id: "csv",
        path: "/api/v1/areas/{code}/csv",
        example_path: "/areas/CIV/csv",
        format: :csv,
        desc:
          t(
            locale,
            "Une ligne par année, une colonne par indicateur et une colonne status (actual, estimate, projection). La première ligne cite la source.",
            "One row per year, one column per indicator and a status column (actual, estimate, projection). The first line cites the source."
          ),
        params: [code],
        ok: t(locale, "Fichier CSV", "CSV file"),
        errors: [{"404", "unknown_area", t(locale, "code de zone inconnu", "unknown area code")}]
      }
    ]
  end

  defp param(name, type, where, required, values, default, role),
    do: %{
      name: name,
      type: type,
      where: where,
      required: required,
      values: values,
      default: default,
      role: role
    }

  defp t("fr", fr, _en), do: fr
  defp t(_, _fr, en), do: en

  # Code in four languages ---------------------------------------------

  @doc false
  def code(%{format: :csv}, url, _base) do
    [
      {"curl", "cURL", CodeHighlight.lines(~s($ curl -O "#{url}"), :shell)},
      {"js", "JavaScript",
       CodeHighlight.lines(
         ~s|const res = await fetch("#{url}");\nconst text = await res.text();\n// one line per year, the source first|,
         :code
       )},
      {"py", "Python",
       CodeHighlight.lines(
         ~s|import pandas as pd\n\nurl = "#{url}"\ndf = pd.read_csv(url, comment="#")\nprint(df[["year", "real_gdp_index"]])|,
         :code
       )},
      {"sheet", "Tableur / Sheets", CodeHighlight.lines(~s|=IMPORTDATA("#{url}")|, :shell)}
    ]
  end

  def code(%{id: id}, url, base) do
    field =
      case id do
        "areas" -> "data.areas.length"
        "area" -> "data.profile.default_period.real_gdp_change_pct"
        "compare" -> "data.map((z) => z.code)"
        "ranking" -> "data[0].name"
        _ -> "data"
      end

    [
      {"curl", "cURL", CodeHighlight.lines(~s($ curl "#{url}"), :shell)},
      {"js", "JavaScript",
       CodeHighlight.lines(
         ~s|const res = await fetch("#{url}");\nconst data = await res.json();\n\nconsole.log(#{field});|,
         :code
       )},
      {"py", "Python",
       CodeHighlight.lines(
         ~s|import requests\n\nr = requests.get("#{url}", timeout=10)\nr.raise_for_status()\ndata = r.json()|,
         :code
       )},
      {"sheet", "Tableur / Sheets",
       CodeHighlight.lines(
         ~s|# spreadsheets read the CSV route\n=IMPORTDATA("#{base}/areas/CIV/csv")|,
         :shell
       )}
    ]
  end

  # Real answers, shortened -------------------------------------------

  @doc "The example answers, built once per data version."
  def examples do
    version = Profiles.data_version()

    case :persistent_term.get({__MODULE__, :examples}, nil) do
      {^version, examples} ->
        examples

      _ ->
        examples = build_examples()
        :persistent_term.put({__MODULE__, :examples}, {version, examples})
        examples
    end
  end

  defp build_examples do
    areas =
      SyliAtlas.Geo.list_areas()
      |> Enum.take(2)
      |> Enum.map(fn a ->
        ordered([
          {"code", a.code},
          {"kind", a.kind},
          {"region", a.region_code},
          {"name", ordered([{"fr", a.name_fr}, {"en", a.name_en}])}
        ])
      end)

    %{
      "areas" => pretty(ordered([{"areas", areas ++ [:more]}])),
      "area" => json_example(Queries.area_profile("CIV", 2020, 2025)),
      "compare" => json_example(Queries.compare(["CIV", "GHA"], 2020, 2025)),
      "ranking" =>
        json_example(
          Queries.ranking("real_gdp_index", 2020, 2025, region: nil, mode: "change", locale: "fr")
        ),
      "csv" => csv_example()
    }
  rescue
    _ -> %{}
  end

  defp csv_example do
    conn =
      Plug.Test.conn(:get, "/api/v1/areas/CIV/csv")
      |> Map.put(:host, SyliAtlasWeb.Endpoint.host())
      |> SyliAtlasWeb.Endpoint.call(SyliAtlasWeb.Endpoint.init([]))

    if conn.status == 200 do
      conn.resp_body
      |> String.split("\n")
      |> Enum.take(4)
      |> Enum.map(&shorten_csv_line/1)
      |> Kernel.++(["…"])
      |> Enum.join("\n")
    else
      ""
    end
  end

  defp shorten_csv_line(line) do
    if String.starts_with?(line, "#") do
      line
    else
      cells = String.split(line, ",")
      if length(cells) > 6, do: Enum.join(Enum.take(cells, 6) ++ ["…"], ","), else: line
    end
  end

  defp json_example(nil), do: ""

  defp json_example(json) do
    case Jason.decode(json, objects: :ordered_objects) do
      {:ok, value} -> value |> shorten(0) |> pretty()
      _ -> ""
    end
  end

  # Lists keep 4 items, objects 7 keys; deep levels fold to {…}.
  @list 4
  @keys 7
  @depth 4

  defp shorten(%Jason.OrderedObject{values: values}, depth) when depth >= @depth and values != [],
    do: :folded_object

  defp shorten(%Jason.OrderedObject{values: values}, depth) do
    kept = values |> Enum.take(@keys) |> Enum.map(fn {k, v} -> {k, shorten(v, depth + 1)} end)
    ordered(if length(values) > @keys, do: kept ++ [:more], else: kept)
  end

  defp shorten(list, depth) when is_list(list) do
    kept = list |> Enum.take(@list) |> Enum.map(&shorten(&1, depth + 1))
    if length(list) > @list, do: kept ++ [:more], else: kept
  end

  defp shorten(value, _depth), do: value

  defp ordered(pairs), do: %Jason.OrderedObject{values: pairs}

  @doc false
  def pretty(value), do: pretty(value, 0)

  defp pretty(%Jason.OrderedObject{values: []}, _), do: "{}"

  defp pretty(%Jason.OrderedObject{values: values}, level) do
    pad = String.duplicate("  ", level + 1)

    if inline?(values) do
      "{ " <> Enum.map_join(values, ", ", &pair(&1, level)) <> " }"
    else
      "{\n" <>
        Enum.map_join(values, ",\n", &(pad <> pair(&1, level))) <>
        "\n" <> String.duplicate("  ", level) <> "}"
    end
  end

  defp pretty([], _), do: "[]"

  defp pretty(list, level) when is_list(list) do
    if Enum.all?(list, &scalar?/1) do
      "[" <> Enum.map_join(list, ", ", &pretty(&1, level)) <> "]"
    else
      pad = String.duplicate("  ", level + 1)

      "[\n" <>
        Enum.map_join(list, ",\n", &(pad <> pretty(&1, level + 1))) <>
        "\n" <> String.duplicate("  ", level) <> "]"
    end
  end

  defp pretty(:more, _), do: "…"
  defp pretty(:folded_object, _), do: "{ … }"
  defp pretty(value, _), do: Jason.encode!(value)

  defp pair(:more, _level), do: "…"
  defp pair({k, v}, level), do: Jason.encode!(k) <> ": " <> pretty(v, level + 1)

  # Small objects of scalars fit on one line: { "fr": "…", "en": "…" }.
  defp inline?(values),
    do:
      length(values) <= 4 and
        Enum.all?(values, fn
          {_, v} -> scalar?(v)
          :more -> true
        end)

  defp scalar?(v) when is_map(v) or is_list(v), do: false
  defp scalar?(_), do: true
end
