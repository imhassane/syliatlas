defmodule SyliAtlasWeb.ApiDoc do
  @moduledoc """
  The content of the API page (`/fr/api`, `/en/api`), built from the OpenAPI
  description (`SyliAtlasWeb.Api.Spec`) and the dictionary
  (`SyliAtlasWeb.Api.Catalog`): routes, parameters with their possible
  values, error codes, the table of every field of each answer, the shared
  schemas, and real answers (asked to the API itself, in process, then
  shortened). Examples are kept in memory until the data changes.
  """
  alias SyliAtlas.Profiles
  alias SyliAtlasWeb.Api.{Catalog, Spec}
  alias SyliAtlasWeb.CodeHighlight

  # Schemas described once, in their own section, and linked from the routes.
  @shared ~w(AreaRef Names Pages Docs Source Years Series Period ChangePercent ChangePoints Rank Position Missing)

  @examples %{
    "areas" => "/areas",
    "area" => "/areas/CIV?from=2020&to=2025",
    "compare" => "/compare?codes=CIV,GHA",
    "ranking" => "/ranking?indicator=real_gdp_index",
    "indicators" => "/indicators",
    "csv" => "/areas/CIV/csv"
  }

  @doc "The schemas described in their own section."
  def shared, do: @shared

  @doc "The routes of the page, in order, in `locale`."
  def routes(locale) do
    base = SyliAtlasWeb.Endpoint.url() <> "/api/v1"
    examples = examples()

    for {id, path, op} <- Spec.operations() do
      url = base <> @examples[id]
      csv? = id == "csv"

      %{
        id: id,
        path: "/api/v1" <> path,
        summary: pick(op, "summary", locale),
        desc:
          if(csv?, do: pick(op, "description", locale), else: response_description(op, locale)),
        format: if(csv?, do: :csv, else: :json),
        params: Enum.map(op["parameters"] || [], &param(&1, locale)),
        errors: errors(op),
        fields: if(csv?, do: [], else: fields(op, locale)),
        code: code(id, url, base),
        response: CodeHighlight.lines(examples[id] || "", if(csv?, do: :csv, else: :json))
      }
    end
  end

  @doc "The schemas shared by several answers, with their fields."
  def shared_schemas(locale) do
    schemas = Spec.schemas()

    for name <- @shared do
      schema = schemas[name]
      %{name: name, desc: pick(schema, "description", locale), fields: walk(schema, "", locale)}
    end
  end

  @doc "Every indicator of the dictionary, in `locale`."
  def indicators(locale) do
    units = Map.new(Catalog.units(), &{&1.code, &1.label})

    for i <- Catalog.indicators() do
      %{
        key: i.key,
        name: label(i.name, locale),
        description: label(i.description, locale),
        unit: label(units[i.unit], locale),
        unit_code: i.unit,
        change_unit: i.change_unit,
        imf_code: i.imf_code
      }
    end
  end

  @doc "Every closed list of values, with labels in `locale`."
  def value_lists(locale) do
    for {name, values} <- [
          {"kind", Catalog.kinds()},
          {"region", Catalog.regions()},
          {"years.status", Catalog.statuses()},
          {"unit", Catalog.units()},
          {"mode", Catalog.modes()}
        ] do
      %{name: name, values: Enum.map(values, &%{code: &1.code, label: label(&1.label, locale)})}
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

  # From the OpenAPI description ----------------------------------------

  defp pick(map, key, "fr"), do: map["x-" <> key <> "-fr"] || map[key]
  defp pick(map, key, "en"), do: map[key]
  defp pick(map, key, locale), do: SyliAtlasWeb.ApiDocI18n.translate(map[key], locale)

  defp label(%{fr: fr}, "fr"), do: fr
  defp label(%{en: en}, "en"), do: en
  defp label(%{en: en}, locale), do: SyliAtlasWeb.ApiDocI18n.translate(en, locale)

  defp response_description(op, locale) do
    schema = resolve(op["responses"]["200"]["content"]["application/json"]["schema"])
    data = resolve(schema["properties"]["data"])
    pick(data, "description", locale) || pick(schema, "description", locale)
  end

  defp param(p, locale) do
    schema = p["schema"]

    values =
      cond do
        schema["enum"] -> Enum.join(schema["enum"], " | ")
        schema["minimum"] -> "#{schema["minimum"]} – #{schema["maximum"]}"
        schema["examples"] -> Enum.join(schema["examples"], ", ") <> "…"
        true -> nil
      end

    %{
      name: p["name"],
      type: schema["type"],
      where: p["in"],
      required: p["required"],
      values: values,
      default: schema["default"],
      role: pick(p, "description", locale)
    }
  end

  defp errors(op) do
    for {status, %{"description" => code}} <- Enum.sort(op["responses"]),
        status not in ["200", "429"],
        do: {status, code}
  end

  defp fields(op, locale) do
    schema = op["responses"]["200"]["content"]["application/json"]["schema"]
    walk(resolve(schema), "", locale)
  end

  # The fields of a schema, depth first, in their declared order. A shared
  # schema is a link, described once in its own section.
  defp walk(%{"properties" => props} = schema, prefix, locale) do
    order = schema["x-order"] || Map.keys(props)
    Enum.flat_map(order, fn name -> field(props[name], prefix <> name, locale) end)
  end

  defp walk(_schema, _prefix, _locale), do: []

  defp field(%{"$ref" => _} = ref, path, locale) do
    name = ref_name(ref)
    schema = Map.merge(resolve(ref), Map.take(ref, ["description", "x-description-fr"]))

    if name in @shared,
      do: [row(path, schema, locale, link: name)],
      else: [row(path, schema, locale) | walk(schema, path <> ".", locale)]
  end

  defp field(%{"anyOf" => [%{"$ref" => _} = ref, %{"type" => "null"}]} = s, path, locale) do
    name = ref_name(ref)
    target = resolve(ref)
    described = Map.merge(target, Map.take(s, ["description", "x-description-fr"]))
    row = row(path, described, locale, link: name, null: true)

    if name in @shared, do: [row], else: [row | walk(target, path <> ".", locale)]
  end

  defp field(%{"type" => "array", "items" => items} = s, path, locale) do
    item_path = path <> "[]"

    case items do
      %{"$ref" => _} = ref ->
        name = ref_name(ref)

        if name in @shared,
          do: [row(path, s, locale, link: name, array: true)],
          else: [row(path, s, locale, array: true) | walk(resolve(ref), item_path <> ".", locale)]

      %{"type" => "object"} = obj ->
        [row(path, s, locale) | walk(obj, item_path <> ".", locale)]

      _ ->
        [row(path, s, locale)]
    end
  end

  defp field(%{"type" => "object", "properties" => _} = s, path, locale),
    do: [row(path, s, locale) | walk(s, path <> ".", locale)]

  defp field(s, path, locale), do: [row(path, s, locale)]

  defp row(path, schema, locale, opts \\ []) do
    %{
      path: path,
      type: type_label(schema, opts),
      link: opts[:link],
      desc: pick(schema, "description", locale),
      values: values_label(schema),
      unit: schema["x-unit"]
    }
  end

  defp type_label(schema, opts) do
    base =
      cond do
        opts[:link] && opts[:array] -> opts[:link] <> "[]"
        opts[:link] -> opts[:link]
        true -> type_text(schema)
      end

    if opts[:null], do: base <> " | null", else: base
  end

  defp type_text(%{"type" => "array", "items" => %{"type" => [_, _ | _]} = items}),
    do: "(" <> type_text(items) <> ")[]"

  defp type_text(%{"type" => "array", "items" => items}), do: type_text(items) <> "[]"
  defp type_text(%{"type" => types}) when is_list(types), do: Enum.join(types, " | ")
  defp type_text(%{"type" => type}), do: type
  defp type_text(%{"$ref" => _} = ref), do: ref_name(ref)
  defp type_text(_), do: "any"

  defp values_label(%{"enum" => values}),
    do: values |> Enum.map(&(&1 || "null")) |> Enum.join(" | ")

  defp values_label(%{"items" => %{"enum" => values}}), do: Enum.join(values, " | ")
  defp values_label(_), do: nil

  defp resolve(%{"$ref" => _} = ref), do: Spec.schemas()[ref_name(ref)]
  defp resolve(schema), do: schema

  defp ref_name(%{"$ref" => "#/components/schemas/" <> name}), do: name

  # Code in four languages ---------------------------------------------

  @doc false
  def code("csv", url, _base) do
    [
      {"curl", "cURL", CodeHighlight.lines(~s($ curl -O "#{url}"), :shell)},
      {"js", "JavaScript",
       CodeHighlight.lines(
         ~s|const res = await fetch("#{url}");\nconst text = await res.text();\n// line 1: the source; then one row per year|,
         :code
       )},
      {"py", "Python",
       CodeHighlight.lines(
         ~s|import pandas as pd\n\nurl = "#{url}"\ndf = pd.read_csv(url, comment="#")\nprint(df[["year", "status", "real_gdp_index"]])|,
         :code
       )},
      {"sheet", "Tableur / Sheets", CodeHighlight.lines(~s|=IMPORTDATA("#{url}")|, :shell)}
    ]
  end

  def code(id, url, base) do
    field =
      case id do
        "areas" -> "data.length"
        "area" -> "data.period.change_percent.real_gdp_index"
        "compare" -> "data.map((a) => a.code)"
        "ranking" -> "data[0].name.fr, data[0].value, meta.unit"
        "indicators" -> "data.map((i) => i.key + \": \" + i.unit)"
        _ -> "data"
      end

    [
      {"curl", "cURL", CodeHighlight.lines(~s($ curl "#{url}"), :shell)},
      {"js", "JavaScript",
       CodeHighlight.lines(
         ~s|const res = await fetch("#{url}");\nconst { data, meta } = await res.json();\n\nconsole.log(#{field});\nconsole.log(meta.sources[0]?.attribution.en);|,
         :code
       )},
      {"py", "Python",
       CodeHighlight.lines(
         ~s|import requests\n\nr = requests.get("#{url}", timeout=10)\nr.raise_for_status()\nbody = r.json()\ndata, meta = body["data"], body["meta"]|,
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

        if Enum.all?(examples, fn {_, text} -> text != "" end),
          do: :persistent_term.put({__MODULE__, :examples}, {version, examples})

        examples
    end
  end

  defp build_examples do
    for {id, path} <- @examples, into: %{} do
      body = call("/api/v1" <> path)

      text =
        cond do
          body == nil -> ""
          id == "csv" -> csv_example(body)
          true -> json_example(body)
        end

      {id, text}
    end
  end

  # Asks the API itself, in process, through the whole stack.
  defp call(path) do
    conn =
      Plug.Test.conn(:get, path)
      |> Map.put(:host, SyliAtlasWeb.Endpoint.host())
      |> SyliAtlasWeb.Endpoint.call(SyliAtlasWeb.Endpoint.init([]))

    if conn.status == 200, do: conn.resp_body
  rescue
    _ -> nil
  end

  defp csv_example(body) do
    body
    |> String.split("\n")
    |> Enum.take(4)
    |> Enum.map(fn line ->
      cells = String.split(line, ",")

      if not String.starts_with?(line, "#") and length(cells) > 6,
        do: Enum.join(Enum.take(cells, 6) ++ ["…"], ","),
        else: line
    end)
    |> Kernel.++(["…"])
    |> Enum.join("\n")
  end

  defp json_example(json) do
    case Jason.decode(json, objects: :ordered_objects) do
      {:ok, value} -> value |> shorten(0) |> pretty()
      _ -> ""
    end
  end

  # Lists keep 3 items (2 at the top of data); objects below the second
  # level keep 4 keys.
  defp shorten(%Jason.OrderedObject{values: values}, depth) do
    kept = if depth >= 3, do: Enum.take(values, 4), else: values
    shortened = Enum.map(kept, fn {k, v} -> {k, shorten(v, depth + 1)} end)
    ordered(if length(values) > length(kept), do: shortened ++ [:more], else: shortened)
  end

  defp shorten(list, depth) when is_list(list) do
    limit = if depth == 1, do: 2, else: 3
    kept = list |> Enum.take(limit) |> Enum.map(&shorten(&1, depth + 1))
    if length(list) > limit, do: kept ++ [:more], else: kept
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
  defp pretty(value, _), do: Jason.encode!(value)

  defp pair(:more, _level), do: "…"
  defp pair({k, v}, level), do: Jason.encode!(k) <> ": " <> pretty(v, level + 1)

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
