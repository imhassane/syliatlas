defmodule SyliAtlas.SchemaValidator do
  @moduledoc """
  Checks a decoded JSON value against a schema of the API description
  (`SyliAtlasWeb.Api.Spec`), for the contract tests. Supports what the
  description uses: `type` (one or a list), `enum`, `properties`,
  `required`, `additionalProperties` (false or a schema), `items`,
  `minimum`/`maximum`, `anyOf` and `$ref` to `#/components/schemas/…`.
  Annotations (`description`, `x-…`, `format`, `default`, `examples`) are
  not checked.

  Returns a list of errors, `[]` when the value is valid.
  """

  @known ~w(type enum properties required additionalProperties items minimum maximum anyOf $ref
            description x-description-fr x-unit x-order format default examples)

  def validate(value, schema, schemas, path \\ "$") do
    unknown = Map.keys(schema) -- @known

    if unknown != [] do
      ["#{path}: schema uses unsupported keywords #{inspect(unknown)}"]
    else
      check(value, schema, schemas, path)
    end
  end

  defp check(value, %{"$ref" => "#/components/schemas/" <> name}, schemas, path) do
    case schemas[name] do
      nil -> ["#{path}: unknown schema #{name}"]
      schema -> validate(value, schema, schemas, path)
    end
  end

  defp check(value, %{"anyOf" => options}, schemas, path) do
    if Enum.any?(options, &(validate(value, &1, schemas, path) == [])),
      do: [],
      else: ["#{path}: matches none of anyOf (#{inspect(value, limit: 3)})"]
  end

  defp check(value, schema, schemas, path) do
    with [] <- check_type(value, schema["type"], path),
         [] <- check_enum(value, schema["enum"], path),
         [] <- check_range(value, schema, path) do
      cond do
        is_map(value) -> check_object(value, schema, schemas, path)
        is_list(value) -> check_items(value, schema["items"], schemas, path)
        true -> []
      end
    end
  end

  defp check_type(_value, nil, _path), do: []

  defp check_type(value, types, path) when is_list(types) do
    if Enum.any?(types, &type?(value, &1)),
      do: [],
      else: ["#{path}: expected #{Enum.join(types, " or ")}, got #{inspect(value, limit: 3)}"]
  end

  defp check_type(value, type, path), do: check_type(value, [type], path)

  defp type?(v, "object"), do: is_map(v)
  defp type?(v, "array"), do: is_list(v)
  defp type?(v, "string"), do: is_binary(v)
  defp type?(v, "integer"), do: is_integer(v)
  defp type?(v, "number"), do: is_number(v)
  defp type?(v, "boolean"), do: is_boolean(v)
  defp type?(v, "null"), do: is_nil(v)

  defp check_enum(_value, nil, _path), do: []

  defp check_enum(value, values, path) do
    if value in values, do: [], else: ["#{path}: #{inspect(value)} not in #{inspect(values)}"]
  end

  defp check_range(value, schema, path) when is_number(value) do
    low = schema["minimum"]
    high = schema["maximum"]

    cond do
      low && value < low -> ["#{path}: #{value} < #{low}"]
      high && value > high -> ["#{path}: #{value} > #{high}"]
      true -> []
    end
  end

  defp check_range(_value, _schema, _path), do: []

  defp check_object(value, schema, schemas, path) do
    props = schema["properties"] || %{}

    missing =
      for key <- schema["required"] || [],
          not Map.has_key?(value, key),
          do: "#{path}: missing #{key}"

    extra =
      case schema["additionalProperties"] do
        false ->
          for key <- Map.keys(value),
              not Map.has_key?(props, key),
              do: "#{path}: undocumented field #{key}"

        %{} = item ->
          for {key, v} <- value,
              not Map.has_key?(props, key),
              e <- validate(v, item, schemas, "#{path}.#{key}"),
              do: e

        _ ->
          []
      end

    nested =
      for {key, sub} <- props,
          Map.has_key?(value, key),
          e <- validate(value[key], sub, schemas, "#{path}.#{key}"),
          do: e

    missing ++ extra ++ nested
  end

  defp check_items(_list, nil, _schemas, _path), do: []

  defp check_items(list, items, schemas, path) do
    list
    |> Enum.with_index()
    |> Enum.flat_map(fn {v, i} -> validate(v, items, schemas, "#{path}[#{i}]") end)
  end
end
