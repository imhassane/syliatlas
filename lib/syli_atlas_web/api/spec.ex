defmodule SyliAtlasWeb.Api.Spec do
  @moduledoc """
  The OpenAPI 3.1 description of API v1, served at `/api/v1/openapi.json`.

  Every field of every answer is described: type, whether it can be null,
  its possible values, its unit, in English (`description`) and French
  (`x-description-fr`). Objects allow no undocumented field
  (`additionalProperties: false`), and the contract tests check every real
  answer against it, so the description cannot fall behind the code. The
  documentation page builds its field tables from it.
  """
  alias SyliAtlas.Sources.Indicators
  alias SyliAtlasWeb.Api.Catalog

  @doc "The whole document, as a map with string keys."
  def document do
    %{
      "openapi" => "3.1.0",
      "info" => %{
        "title" => "Syli Atlas API",
        "version" => "1.0.0",
        "summary" =>
          "Economic indicators of the 54 African countries, the regions and the continent.",
        "description" =>
          "Read-only, free, no key. JSON answers are {data, meta}; meta.sources gives the attribution to copy. Each figure keeps the licence of its source.",
        "x-description-fr" =>
          "Lecture seule, gratuite, sans clé. Les réponses JSON sont {data, meta} ; meta.sources donne l'attribution à reprendre. Chaque chiffre garde la licence de sa source.",
        "contact" => %{"url" => SyliAtlasWeb.Endpoint.url() <> "/en/api"}
      },
      "servers" => [%{"url" => SyliAtlasWeb.Endpoint.url() <> "/api/v1"}],
      "paths" => paths(),
      "components" => %{"schemas" => schemas()}
    }
  end

  @doc "The routes, in page order: `{id, path, operation}`."
  def operations do
    [
      {"areas", "/areas", areas_op()},
      {"area", "/areas/{code}", area_op()},
      {"compare", "/compare", compare_op()},
      {"ranking", "/ranking", ranking_op()},
      {"indicators", "/indicators", indicators_op()},
      {"csv", "/areas/{code}/csv", csv_op()}
    ]
  end

  defp paths do
    ops = Map.new(operations(), fn {_id, path, op} -> {path, %{"get" => op}} end)

    Map.merge(ops, %{
      "/" => %{"get" => index_op()},
      "/openapi.json" => %{
        "get" => %{
          "operationId" => "openapi",
          "summary" => "This document",
          "x-summary-fr" => "Ce document",
          "responses" => %{"200" => %{"description" => "OpenAPI 3.1"}}
        }
      }
    })
  end

  # Operations --------------------------------------------------------

  defp areas_op do
    op("listAreas", "Every area", "Toutes les zones", [], "AreaList", [])
  end

  defp area_op do
    op(
      "getArea",
      "One area, every series",
      "Une zone, toutes ses séries",
      [code(), from(), to()],
      "AreaAnswer",
      [
        {"400", "invalid_period"},
        {"404", "unknown_area"}
      ]
    )
  end

  defp compare_op do
    codes =
      param(
        "codes",
        "query",
        true,
        %{"type" => "string", "examples" => ["CIV,GHA,SEN"]},
        "2 to 6 area codes, separated by commas. Unknown codes are left out of data.",
        "2 à 6 codes de zone séparés par des virgules. Les codes inconnus sont absents de data."
      )

    op(
      "compareAreas",
      "Several areas side by side",
      "Plusieurs zones côte à côte",
      [codes, from(), to()],
      "CompareAnswer",
      [
        {"400", "codes_required"},
        {"400", "invalid_period"}
      ]
    )
  end

  defp ranking_op do
    params = [
      param(
        "indicator",
        "query",
        false,
        %{"type" => "string", "enum" => Catalog.indicator_keys(), "default" => "real_gdp_index"},
        "Indicator to rank (see /indicators).",
        "Indicateur à classer (voir /indicators)."
      ),
      param(
        "mode",
        "query",
        false,
        %{"type" => "string", "enum" => Catalog.codes(Catalog.modes()), "default" => "change"},
        "change: change between from and to; value: value in the year to.",
        "change : variation entre from et to ; value : valeur de l'année to."
      ),
      param(
        "region",
        "query",
        false,
        %{"type" => "string", "enum" => Catalog.codes(Catalog.regions())},
        "Keep the countries of one region.",
        "Ne garder que les pays d'une région."
      ),
      from(),
      to()
    ]

    op(
      "rankCountries",
      "Countries ranked on an indicator",
      "Les pays classés selon un indicateur",
      params,
      "RankingAnswer",
      [
        {"400", "unknown_indicator"},
        {"400", "invalid_period"}
      ]
    )
  end

  defp indicators_op do
    op(
      "listIndicators",
      "The indicators: unit, meaning, source",
      "Les indicateurs : unité, définition, source",
      [],
      "IndicatorList",
      []
    )
  end

  defp csv_op do
    columns = Enum.join(["year", "status" | Catalog.indicator_keys()], ", ")

    %{
      "operationId" => "getAreaCsv",
      "summary" => "One area as CSV",
      "x-summary-fr" => "Une zone en CSV",
      "description" =>
        "Line 1 is a comment (#) naming the source. Then a header and one row per year from #{Indicators.first_year()} to #{Indicators.last_year()}. Columns: #{columns}. status is actual, estimate or projection; empty cell = no value. Units: see /indicators.",
      "x-description-fr" =>
        "La ligne 1 est un commentaire (#) qui nomme la source. Puis un en-tête et une ligne par année de #{Indicators.first_year()} à #{Indicators.last_year()}. Colonnes : #{columns}. status vaut actual, estimate ou projection ; cellule vide = pas de valeur. Unités : voir /indicators.",
      "parameters" => [code()],
      "responses" => %{
        "200" => %{
          "description" => "CSV",
          "content" => %{"text/csv" => %{"schema" => %{"type" => "string"}}}
        },
        "404" => error_response("unknown_area"),
        "429" => error_response("rate_limited")
      }
    }
  end

  defp index_op do
    %{
      "operationId" => "index",
      "summary" => "Table of contents: routes, documentation, closed lists of values",
      "x-summary-fr" => "Sommaire : routes, documentation, listes de valeurs",
      "responses" => %{
        "200" => %{
          "description" => "OK",
          "content" => %{"application/json" => %{"schema" => ref("Index")}}
        }
      }
    }
  end

  defp op(id, summary, summary_fr, params, schema, errors) do
    responses =
      Map.new(errors, fn {status, code} -> {status, error_response(code)} end)
      |> Map.put("429", error_response("rate_limited"))
      |> Map.put("200", %{
        "description" => "OK",
        "content" => %{"application/json" => %{"schema" => ref(schema)}}
      })

    %{
      "operationId" => id,
      "summary" => summary,
      "x-summary-fr" => summary_fr,
      "parameters" => params,
      "responses" => responses
    }
  end

  defp error_response(code) do
    %{
      "description" => code,
      "content" => %{"application/json" => %{"schema" => ref("Error")}}
    }
  end

  defp code do
    param(
      "code",
      "path",
      true,
      %{"type" => "string", "examples" => ["CIV", "west_africa", "africa"]},
      "Area code: ISO 3 for a country, a region code, africa, or an IMF aggregate (see /areas).",
      "Code de la zone : ISO 3 pour un pays, code de région, africa, ou agrégat du FMI (voir /areas)."
    )
  end

  defp from do
    param(
      "from",
      "query",
      false,
      year(2020),
      "First year of the period.",
      "Année de départ de la période."
    )
  end

  defp to do
    param(
      "to",
      "query",
      false,
      year(2025),
      "Last year of the period, after from.",
      "Année d'arrivée, après from."
    )
  end

  defp year(default),
    do: %{
      "type" => "integer",
      "minimum" => Indicators.first_year(),
      "maximum" => Indicators.last_year(),
      "default" => default
    }

  defp param(name, location, required, schema, en, fr) do
    %{
      "name" => name,
      "in" => location,
      "required" => required,
      "schema" => schema,
      "description" => en,
      "x-description-fr" => fr
    }
  end

  # Schemas -----------------------------------------------------------

  @doc "The component schemas, by name."
  def schemas do
    %{
      "Names" =>
        obj(
          [
            {"fr", str("In French.", "En français.")},
            {"en", str("In English.", "En anglais.")}
          ],
          "A text in French and English.",
          "Un texte en français et en anglais."
        ),
      "Pages" =>
        obj(
          [
            {"fr", str("Page in French.", "Page en français.", format: "uri")},
            {"en", str("Page in English.", "Page en anglais.", format: "uri")}
          ],
          "The area's page on the site.",
          "La page de la zone sur le site."
        ),
      "AreaRef" => obj(area_ref_props(), "An area.", "Une zone."),
      "Years" =>
        obj(
          [
            {"first", int("First year of the series.", "Première année des séries.")},
            {"last", int("Last year of the series.", "Dernière année des séries.")},
            {"estimate_from",
             int("First year estimated by the IMF.", "Première année estimée par le FMI.")},
            {"projection_from",
             int("First year projected by the IMF.", "Première année projetée par le FMI.")},
            {"list",
             arr(
               %{"type" => "integer"},
               "Every year; position i of each series is year list[i].",
               "Toutes les années ; la position i de chaque série est l'année list[i]."
             )},
            {"status",
             arr(
               enum(Catalog.codes(Catalog.statuses())),
               "Status of each year, aligned with list.",
               "Statut de chaque année, aligné sur list."
             )}
          ],
          "The years of the series.",
          "Les années des séries."
        ),
      "Series" =>
        obj(
          for i <- Catalog.indicators() do
            {i.key,
             arr(
               %{"type" => ["number", "null"]},
               "#{i.name.en}, #{unit_label(i.unit, :en)}, one value per year of years.list (null: no value).",
               "#{i.name.fr}, #{unit_label(i.unit, :fr)}, une valeur par année de years.list (null : pas de valeur).",
               unit: i.unit
             )}
          end,
          "One list per indicator, aligned with years.list.",
          "Une liste par indicateur, alignée sur years.list."
        ),
      "ChangePercent" =>
        obj(
          for i <- Catalog.indicators(), i.change_unit == "percent" do
            {i.key,
             num_or_null(
               "Change of #{i.name.en} between from and to, in %.",
               "Variation de #{i.name.fr} entre from et to, en %.",
               unit: "percent"
             )}
          end,
          "Changes of levels and of the index, in percent.",
          "Variations des niveaux et de l'indice, en pourcentage."
        ),
      "ChangePoints" =>
        obj(
          for i <- Catalog.indicators(), i.change_unit == "points" do
            {i.key,
             num_or_null(
               "Change of #{i.name.en} between from and to, in percentage points.",
               "Écart de #{i.name.fr} entre from et to, en points de pourcentage.",
               unit: "points"
             )}
          end,
          "Changes of rates, in percentage points.",
          "Écarts des taux, en points de pourcentage."
        ),
      "Period" =>
        obj(
          [
            {"from", int("First year of the period.", "Année de départ.")},
            {"to", int("Last year of the period.", "Année d'arrivée.")},
            {"change_percent", ref("ChangePercent")},
            {"change_points", ref("ChangePoints")}
          ],
          "Changes over the asked period. null when a year has no value.",
          "Variations sur la période demandée. null quand une année n'a pas de valeur."
        ),
      "Position" =>
        obj(
          [
            {"position", int("Place, 1 = highest growth.", "Place, 1 = plus forte croissance.")},
            {"out_of", int("Number of countries ranked.", "Nombre de pays classés.")}
          ],
          "A place in a ranking.",
          "Une place dans un classement."
        ),
      "Rank" =>
        obj(
          [
            {"from",
             int(
               "First year of the ranking period (fixed).",
               "Année de départ du classement (fixe)."
             )},
            {"to",
             int(
               "Last year of the ranking period (fixed).",
               "Année d'arrivée du classement (fixe)."
             )},
            {"indicator", enum(["real_gdp_index"], "Indicator ranked.", "Indicateur classé.")},
            {"change_percent",
             num_or_null(
               "Real GDP growth over the period, in %.",
               "Croissance du PIB réel sur la période, en %.",
               unit: "percent"
             )},
            {"africa", ref("Position")},
            {"region", ref("Position")}
          ],
          "The country's place by real GDP growth over the default period, in Africa and in its region. Computed once per edition, so independent of from and to.",
          "La place du pays par croissance du PIB réel sur la période par défaut, en Afrique et dans sa région. Calculée une fois par édition : ne dépend pas de from et to."
        ),
      "Missing" =>
        obj(
          [
            {"indicator", enum(Catalog.indicator_keys(), "Indicator.", "Indicateur.")},
            {"years",
             arr(%{"type" => "integer"}, "Years without a value.", "Années sans valeur.")}
          ],
          "A gap in a series.",
          "Un trou dans une série."
        ),
      "Area" =>
        obj(
          area_ref_props() ++
            [
              {"members",
               arr(
                 %{"type" => "string"},
                 "Country codes making up a region or the continent. Empty for a country and for IMF aggregates (their composition is the IMF's).",
                 "Codes des pays qui composent une région ou le continent. Vide pour un pays et pour les agrégats du FMI (composition du FMI)."
               )},
              {"years", ref("Years")},
              {"series", ref("Series")},
              {"share_of_africa_gdp",
               arr(
                 %{"type" => ["number", "null"]},
                 "Share of Africa's GDP in current dollars, in %, aligned with years.list. Computed by Syli Atlas.",
                 "Part du PIB de l'Afrique en dollars courants, en %, alignée sur years.list. Calcul Syli Atlas.",
                 unit: "percent"
               )},
              {"missing",
               arr(
                 ref("Missing"),
                 "Gaps in the series, as published by the IMF.",
                 "Trous dans les séries, tels que publiés par le FMI."
               )},
              {"period", ref("Period")},
              {"rank",
               nullable_ref(
                 "Rank",
                 "null for regions, the continent and IMF aggregates.",
                 "null pour les régions, le continent et les agrégats du FMI."
               )}
            ],
          "An area with every series.",
          "Une zone avec toutes ses séries."
        ),
      "CompareItem" =>
        obj(
          area_ref_props() ++
            [{"years", ref("Years")}, {"series", ref("Series")}, {"period", ref("Period")}],
          "An area in a comparison.",
          "Une zone dans une comparaison."
        ),
      "RankingItem" =>
        obj(
          area_ref_props() ++
            [
              {"position",
               int_or_null(
                 "Place, 1 = highest value; null when the country has no value.",
                 "Place, 1 = valeur la plus haute ; null quand le pays n'a pas de valeur."
               )},
              {"value",
               num_or_null(
                 "The ranked value, in meta.unit.",
                 "La valeur classée, dans l'unité meta.unit."
               )}
            ],
          "A ranked country.",
          "Un pays classé."
        ),
      "Indicator" =>
        obj(
          [
            {"key",
             enum(
               Catalog.indicator_keys(),
               "Key used in series and parameters.",
               "Clé utilisée dans les séries et les paramètres."
             )},
            {"name", ref("Names", "Name of the indicator.", "Nom de l'indicateur.")},
            {"description", ref("Names", "What it measures.", "Ce qu'il mesure.")},
            {"unit",
             enum(
               Catalog.unit_codes(),
               "Unit of the values (labels in the documentation).",
               "Unité des valeurs (libellés dans la documentation)."
             )},
            {"kind",
             enum(
               ["rate", "level", "index"],
               "rate: already a percentage; level: an amount; index: 100 in 2015.",
               "rate : déjà un pourcentage ; level : un montant ; index : 100 en 2015."
             )},
            {"change_unit",
             enum(
               ["percent", "points"],
               "Unit of its changes: points for rates, percent otherwise.",
               "Unité de ses variations : points pour les taux, pourcentage sinon."
             )},
            {"source",
             obj(
               [
                 {"id", enum(["imf_weo"], "Source.", "Source.")},
                 {"code",
                  str_or_null(
                    "Code of the series at the source (IMF DataMapper); null when computed by Syli Atlas.",
                    "Code de la série chez la source (FMI DataMapper) ; null si calculé par Syli Atlas."
                  )}
               ],
               "Where it comes from.",
               "D'où il vient."
             )}
          ],
          "An indicator.",
          "Un indicateur."
        ),
      "Source" =>
        obj(
          [
            {"id", enum(["imf_weo"], "Source code.", "Code de la source.")},
            {"name", ref("Names", "Name of the source.", "Nom de la source.")},
            {"publisher", ref("Names", "Who publishes it.", "Qui la publie.")},
            {"edition", str("Edition, YYYY-MM.", "Édition, AAAA-MM.")},
            {"label",
             str("Edition's title at the source.", "Titre de l'édition chez la source.")},
            {"url", str("The source's page.", "La page de la source.", format: "uri")},
            {"licence", str("Terms of reuse.", "Conditions de réutilisation.")},
            {"licence_url", str("The terms.", "Les conditions.", format: "uri")},
            {"attribution",
             ref(
               "Names",
               "The sentence to copy under the figures.",
               "La phrase à reprendre sous les chiffres."
             )}
          ],
          "A source of the figures, with the attribution to copy (attribution.fr or attribution.en).",
          "Une source des chiffres, avec l'attribution à reprendre (attribution.fr ou attribution.en)."
        ),
      "Docs" =>
        obj(
          [
            {"fr", str("Documentation in French.", "Documentation en français.", format: "uri")},
            {"en", str("Documentation in English.", "Documentation en anglais.", format: "uri")}
          ],
          "This documentation.",
          "Cette documentation."
        ),
      "AreaList" =>
        answer(
          arr(
            ref("AreaRef"),
            "Every area: countries, regions, the continent, IMF aggregates.",
            "Toutes les zones : pays, régions, continent, agrégats du FMI."
          ),
          [
            {"count", int("Number of areas.", "Nombre de zones.")}
          ]
        ),
      "AreaAnswer" => answer(ref("Area"), period_meta()),
      "CompareAnswer" =>
        answer(
          arr(
            ref("CompareItem"),
            "The areas found, in the asked order.",
            "Les zones trouvées, dans l'ordre demandé."
          ),
          period_meta() ++
            [
              {"codes", arr(%{"type" => "string"}, "The codes asked.", "Les codes demandés.")}
            ]
        ),
      "RankingAnswer" =>
        answer(
          arr(
            ref("RankingItem"),
            "Countries, highest value first; without a value last.",
            "Les pays, valeur la plus haute d'abord ; sans valeur en dernier."
          ),
          period_meta() ++
            [
              {"indicator",
               enum(Catalog.indicator_keys(), "Indicator ranked.", "Indicateur classé.")},
              {"mode",
               enum(Catalog.codes(Catalog.modes()), "change or value.", "change ou value.")},
              {"unit",
               enum(
                 Catalog.unit_codes(),
                 "Unit of value: the indicator's unit (mode value) or its change unit (mode change).",
                 "Unité de value : celle de l'indicateur (mode value) ou de sa variation (mode change)."
               )},
              {"region",
               %{
                 "type" => ["string", "null"],
                 "enum" => Catalog.codes(Catalog.regions()) ++ [nil],
                 "description" => "Region kept, or null for all.",
                 "x-description-fr" => "Région gardée, ou null pour toutes."
               }}
            ]
        ),
      "IndicatorList" =>
        answer(
          arr(
            ref("Indicator"),
            "Every indicator, in the order of the series.",
            "Tous les indicateurs, dans l'ordre des séries."
          ),
          [
            {"years",
             obj(
               [
                 {"first", int("First year.", "Première année.")},
                 {"last", int("Last year.", "Dernière année.")}
               ],
               "Years covered.",
               "Années couvertes."
             )}
          ]
        ),
      "Index" =>
        obj(
          [
            {"name", str("Name.", "Nom.")},
            {"version", str("API version.", "Version de l'API.")},
            {"docs", ref("Docs")},
            {"openapi",
             str("This description, OpenAPI 3.1.", "Cette description, OpenAPI 3.1.",
               format: "uri"
             )},
            {"routes",
             %{
               "type" => "object",
               "additionalProperties" => %{"type" => "string"},
               "description" => "Every route, by name.",
               "x-description-fr" => "Chaque route, par nom."
             }},
            {"values", values_schema()},
            {"limits",
             obj(
               [
                 {"requests_per_minute", int("Per visitor address.", "Par adresse de visiteur.")},
                 {"cache_seconds",
                  int("How long answers may be kept.", "Durée de conservation des réponses.")}
               ],
               "Limits.",
               "Limites."
             )}
          ],
          "Table of contents.",
          "Sommaire."
        ),
      "Error" =>
        obj(
          [
            {"error",
             obj(
               [
                 {"code",
                  enum(
                    ~w(invalid_period codes_required unknown_indicator unknown_area not_found rate_limited),
                    "Stable code, to test in programs.",
                    "Code stable, à tester dans vos programmes."
                  )},
                 {"message", str("Explanation, in English.", "Explication, en anglais.")},
                 {"docs",
                  str_or_null("Where errors are documented.", "Où les erreurs sont documentées.")}
               ],
               "The error.",
               "L'erreur."
             )}
          ],
          "An error.",
          "Une erreur."
        )
    }
  end

  defp area_ref_props do
    [
      {"code",
       str(
         "Code: ISO 3 for a country (CIV), otherwise the area's code (west_africa, africa, SSA).",
         "Code : ISO 3 pour un pays (CIV), sinon le code de la zone (west_africa, africa, SSA)."
       )},
      {"kind", enum(Catalog.codes(Catalog.kinds()), "What the area is.", "Nature de la zone.")},
      {"region",
       %{
         "type" => ["string", "null"],
         "enum" => Catalog.codes(Catalog.regions()) ++ [nil],
         "description" => "African Union region of a country; null otherwise.",
         "x-description-fr" => "Région de l'Union africaine d'un pays ; null sinon."
       }},
      {"name", ref("Names", "Name of the area.", "Nom de la zone.")},
      {"slug",
       ref(
         "Names",
         "Slug of the area's page addresses.",
         "Segment des adresses des pages de la zone."
       )},
      {"pages",
       nullable_ref(
         "Pages",
         "null for IMF aggregates, which have no page.",
         "null pour les agrégats du FMI, qui n'ont pas de page."
       )}
    ]
  end

  defp period_meta do
    [
      {"from", int("First year used.", "Année de départ utilisée.")},
      {"to", int("Last year used.", "Année d'arrivée utilisée.")}
    ]
  end

  defp values_schema do
    item = fn en, fr ->
      arr(
        obj(
          [
            {"code", str("Value.", "Valeur.")},
            {"label", ref("Names", "Its label.", "Son libellé.")}
          ],
          "A value and its label.",
          "Une valeur et son libellé."
        ),
        en,
        fr
      )
    end

    obj(
      [
        {"kind", item.("Possible values of kind.", "Valeurs possibles de kind.")},
        {"region", item.("Possible values of region.", "Valeurs possibles de region.")},
        {"status",
         item.("Possible values of years.status.", "Valeurs possibles de years.status.")},
        {"unit", item.("Units.", "Unités.")},
        {"mode", item.("Ranking modes.", "Modes du classement.")}
      ],
      "Every closed list of values, with labels.",
      "Toutes les listes de valeurs, avec leurs libellés."
    )
  end

  defp answer(data, meta_extra) do
    obj(
      [
        {"data", data},
        {"meta",
         obj(
           [
             {"sources",
              arr(
                ref("Source"),
                "Sources of the figures in data. Empty when data holds no figure.",
                "Sources des chiffres de data. Vide quand data ne contient aucun chiffre."
              )},
             {"docs", ref("Docs")}
           ] ++ meta_extra,
           "About the answer.",
           "À propos de la réponse."
         )}
      ],
      "The answer: data, then meta.",
      "La réponse : data, puis meta."
    )
  end

  @doc """
  Puts the keys of an answer in the documented order (`x-order`), at every
  level, so that answers read like the documentation: identity first, then
  the figures, then `meta`. `schema` is a schema name or a schema.
  """
  def ordered(value, schema) when is_binary(schema), do: ordered(value, schemas()[schema])
  def ordered(value, schema), do: order(value, schema, schemas())

  defp order(value, %{"$ref" => "#/components/schemas/" <> name}, all),
    do: order(value, all[name], all)

  defp order(nil, _schema, _all), do: nil

  defp order(value, %{"anyOf" => options}, all) do
    case Enum.find(options, &Map.has_key?(&1, "$ref")) do
      nil -> value
      ref -> order(value, ref, all)
    end
  end

  defp order(value, %{"x-order" => keys, "properties" => props}, all) when is_map(value) do
    value = Map.new(value, fn {k, v} -> {to_string(k), v} end)
    known = for k <- keys, Map.has_key?(value, k), do: {k, order(value[k], props[k], all)}
    extra = for {k, v} <- value, k not in keys, do: {k, v}
    %Jason.OrderedObject{values: known ++ extra}
  end

  defp order(value, %{"items" => items}, all) when is_list(value),
    do: Enum.map(value, &order(&1, items, all))

  defp order(value, _schema, _all), do: value

  # Builders ----------------------------------------------------------

  @doc false
  def obj(props, en, fr) do
    %{
      "type" => "object",
      "description" => en,
      "x-description-fr" => fr,
      "properties" => Map.new(props),
      "required" => Enum.map(props, &elem(&1, 0)),
      "additionalProperties" => false,
      "x-order" => Enum.map(props, &elem(&1, 0))
    }
  end

  defp str(en, fr, opts \\ []), do: leaf("string", en, fr, opts)
  defp int(en, fr), do: leaf("integer", en, fr, [])
  defp str_or_null(en, fr), do: leaf(["string", "null"], en, fr, [])
  defp int_or_null(en, fr), do: leaf(["integer", "null"], en, fr, [])
  defp num_or_null(en, fr, opts \\ []), do: leaf(["number", "null"], en, fr, opts)

  defp leaf(type, en, fr, opts) do
    %{"type" => type, "description" => en, "x-description-fr" => fr}
    |> put_opt("format", opts[:format])
    |> put_opt("x-unit", opts[:unit])
  end

  defp enum(values), do: %{"type" => "string", "enum" => values}

  defp enum(values, en, fr),
    do: %{"type" => "string", "enum" => values, "description" => en, "x-description-fr" => fr}

  defp arr(items, en, fr, opts \\ []) do
    %{"type" => "array", "items" => items, "description" => en, "x-description-fr" => fr}
    |> put_opt("x-unit", opts[:unit])
  end

  defp ref(name), do: %{"$ref" => "#/components/schemas/" <> name}

  defp ref(name, en, fr),
    do: %{
      "$ref" => "#/components/schemas/" <> name,
      "description" => en,
      "x-description-fr" => fr
    }

  defp nullable_ref(name, en, fr),
    do: %{
      "anyOf" => [ref(name), %{"type" => "null"}],
      "description" => en,
      "x-description-fr" => fr
    }

  defp put_opt(map, _key, nil), do: map
  defp put_opt(map, key, value), do: Map.put(map, key, value)

  defp unit_label(code, lang),
    do: Enum.find_value(Catalog.units(), fn u -> u.code == code && Map.fetch!(u.label, lang) end)
end
