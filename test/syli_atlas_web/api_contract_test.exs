defmodule SyliAtlasWeb.ApiContractTest do
  @moduledoc """
  The API keeps its word: every answer matches its description in
  /api/v1/openapi.json, field by field, with no undocumented field; and the
  description itself is complete (every field explained in both languages,
  every closed list given).
  """
  use SyliAtlasWeb.ConnCase, async: false

  alias SyliAtlas.SchemaValidator
  alias SyliAtlasWeb.Api.{Catalog, Spec}

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    :ok
  end

  defp schema_of(path) do
    op = Spec.document()["paths"][path]["get"]
    op["responses"]["200"]["content"]["application/json"]["schema"]
  end

  defp assert_matches(body, schema) do
    errors = SchemaValidator.validate(body, schema, Spec.schemas())

    assert errors == [],
           "answer does not match its description:\n" <> Enum.join(Enum.take(errors, 20), "\n")
  end

  @cases [
    {"/areas", ["/api/v1/areas"]},
    {"/areas/{code}",
     [
       "/api/v1/areas/CIV",
       "/api/v1/areas/CIV?from=2015&to=2030",
       "/api/v1/areas/west_africa",
       "/api/v1/areas/africa",
       "/api/v1/areas/WLD",
       "/api/v1/areas/SSA"
     ]},
    {"/compare", ["/api/v1/compare?codes=CIV,GHA", "/api/v1/compare?codes=africa,WLD,XXX"]},
    {"/ranking",
     [
       "/api/v1/ranking",
       "/api/v1/ranking?mode=value&indicator=inflation",
       "/api/v1/ranking?indicator=unemployment&region=west_africa&from=2015&to=2030"
     ]},
    {"/indicators", ["/api/v1/indicators"]},
    {"/", ["/api/v1"]}
  ]

  for {path, urls} <- @cases, url <- urls do
    test "GET #{url} matches #{path}" do
      body = build_conn() |> get(unquote(url)) |> json_response(200)
      assert_matches(body, schema_of(unquote(path)))
    end
  end

  test "every area of /areas has a valid profile" do
    %{"data" => areas} = build_conn() |> get("/api/v1/areas") |> json_response(200)

    for %{"code" => code} <- areas do
      body = build_conn() |> get("/api/v1/areas/#{code}") |> json_response(200)
      assert_matches(body, schema_of("/areas/{code}"))
    end
  end

  test "errors match the Error schema" do
    for {url, status} <- [
          {"/api/v1/areas/XXX", 404},
          {"/api/v1/areas/CIV?from=1990", 400},
          {"/api/v1/compare", 400},
          {"/api/v1/ranking?indicator=nope", 400},
          {"/api/v1/nothing", 404}
        ] do
      body = build_conn() |> get(url) |> json_response(status)
      assert_matches(body, %{"$ref" => "#/components/schemas/Error"})
    end
  end

  test "the CSV has the documented columns" do
    [_source, header | rows] =
      build_conn()
      |> get("/api/v1/areas/CIV/csv")
      |> response(200)
      |> String.split("\n", trim: true)

    assert header == Enum.join(["year", "status" | Catalog.indicator_keys()], ",")
    assert length(rows) == length(SyliAtlas.Sources.Indicators.years())

    assert Enum.all?(
             rows,
             &(Enum.at(String.split(&1, ","), 1) in Catalog.codes(Catalog.statuses()))
           )
  end

  test "series, changes and the dictionary cover the same indicators" do
    keys = Catalog.indicator_keys()
    schemas = Spec.schemas()

    assert Map.keys(schemas["Series"]["properties"]) |> Enum.sort() == Enum.sort(keys)

    changes =
      Map.keys(schemas["ChangePercent"]["properties"]) ++
        Map.keys(schemas["ChangePoints"]["properties"])

    assert Enum.sort(changes) == Enum.sort(keys)
    assert Enum.sort(keys) == Enum.sort(SyliAtlas.Sources.Indicators.published_keys())
  end

  test "the description is complete: every field explained in English and French" do
    schemas = Spec.schemas()

    problems =
      for {name, schema} <- schemas, problem <- incomplete(schema, name), do: problem

    assert problems == [], Enum.join(problems, "\n")

    for {_path, %{"get" => op}} <- Spec.document()["paths"], p <- op["parameters"] || [] do
      assert p["description"] && p["x-description-fr"], "parameter #{p["name"]} undescribed"
    end
  end

  # An object lists its fields, allows no other, and every field says what it
  # is in both languages (a $ref is described by its target).
  defp incomplete(%{"type" => "object", "properties" => props} = s, path) do
    own =
      [
        {s["additionalProperties"] == false, "#{path}: additionalProperties must be false"},
        {Enum.sort(s["required"] || []) == Enum.sort(Map.keys(props)),
         "#{path}: every field must be required (null is explicit)"},
        {described?(s), "#{path}: undescribed"}
      ]
      |> Enum.reject(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))

    own ++
      Enum.flat_map(props, fn {key, sub} ->
        field_path = "#{path}.#{key}"

        mine =
          if Map.has_key?(sub, "$ref") or described?(sub),
            do: [],
            else: [field_path <> ": undescribed"]

        mine ++ incomplete(sub, field_path)
      end)
  end

  defp incomplete(%{"type" => "array", "items" => items}, path),
    do: incomplete(items, path <> "[]")

  defp incomplete(%{"anyOf" => options}, path), do: Enum.flat_map(options, &incomplete(&1, path))
  defp incomplete(_schema, _path), do: []

  defp described?(s), do: is_binary(s["description"]) and is_binary(s["x-description-fr"])

  test "keys come in the documented order", %{conn: conn} do
    body = conn |> get("/api/v1/areas/CIV") |> response(200)
    {:ok, %Jason.OrderedObject{values: top}} = Jason.decode(body, objects: :ordered_objects)
    assert Enum.map(top, &elem(&1, 0)) == ["data", "meta"]

    {_, %Jason.OrderedObject{values: data}} = hd(top)
    assert data |> Enum.map(&elem(&1, 0)) |> Enum.take(6) == ~w(code kind region name slug pages)
  end

  test "the OpenAPI document is served", %{conn: conn} do
    doc = conn |> get("/api/v1/openapi.json") |> json_response(200)
    assert doc["openapi"] == "3.1.0"
    assert Map.has_key?(doc["paths"], "/areas/{code}")
  end
end
