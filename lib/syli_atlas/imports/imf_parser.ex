defmodule SyliAtlas.Imports.ImfParser do
  @moduledoc "Turns DataMapper payloads into observation rows."
  alias SyliAtlas.Sources.Indicators

  @months ~w(January February March April May June July August September October November December)

  @doc ~S"""
  Edition code from the label.

      iex> SyliAtlas.Imports.ImfParser.edition_code("World Economic Outlook (October 2026)")
      {:ok, "2026-10"}
  """
  def edition_code(label) do
    case Regex.run(~r/\((\w+) (\d{4})\)/, label || "") do
      [_, month, year] ->
        case Enum.find_index(@months, &(&1 == month)) do
          nil -> {:error, :unknown_month}
          i -> {:ok, "#{year}-#{String.pad_leading(Integer.to_string(i + 1), 2, "0")}"}
        end

      _ ->
        {:error, :unrecognized_label}
    end
  end

  @doc "Rows for the given areas (`%{imf_code => area_code}`) and published years."
  def rows(%{"values" => values}, imf_to_area) do
    years = Indicators.years()

    for %{key: key, imf: imf} <- Indicators.all(),
        {imf_area, by_year} <- Map.get(values, imf, %{}),
        area_code = Map.get(imf_to_area, imf_area),
        area_code != nil,
        year <- years do
      value = by_year[Integer.to_string(year)]
      %{area_code: area_code, indicator: key, year: year, value: value && value * 1.0}
    end
  end
end
