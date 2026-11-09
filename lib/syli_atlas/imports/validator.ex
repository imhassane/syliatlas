defmodule SyliAtlas.Imports.Validator do
  @moduledoc """
  Checks an edition before it goes online. Errors block the publication;
  warnings are shown in the admin and on the affected pages.
  """
  alias SyliAtlas.Sources.Indicators

  def validate(rows, countries) do
    by_area = Enum.group_by(rows, & &1.area_code)
    country_codes = Enum.map(countries, & &1.code)

    present = Enum.filter(country_codes, &Map.has_key?(by_area, &1))
    missing_countries = country_codes -- present

    negative =
      Enum.filter(rows, fn r ->
        r.indicator in ["gdp_usd_bn", "population_m"] and is_number(r.value) and r.value < 0
      end)

    errors =
      []
      |> add_if(
        length(present) < div(length(country_codes) * 9, 10),
        "fewer than 90% of countries present"
      )
      |> add_if(negative != [], "negative GDP or population values")

    warnings =
      Enum.map(missing_countries, &"#{&1}: no data in this edition") ++
        gaps(by_area, country_codes)

    stats = %{
      "rows" => length(rows),
      "values" => Enum.count(rows, &is_number(&1.value)),
      "countries" => length(present),
      "indicators" => rows |> Enum.map(& &1.indicator) |> Enum.uniq() |> length()
    }

    if errors == [], do: {:ok, stats, warnings}, else: {:error, errors, warnings}
  end

  defp gaps(by_area, country_codes) do
    for code <- country_codes,
        rows = Map.get(by_area, code, []),
        rows != [],
        %{key: key} <- Indicators.all(),
        years = for(r <- rows, r.indicator == key, is_nil(r.value), do: r.year),
        years != [] do
      "#{code}: #{key} missing for #{range(years)}"
    end
  end

  defp range(years) do
    sorted = Enum.sort(years)
    if length(sorted) == 1, do: "#{hd(sorted)}", else: "#{hd(sorted)}-#{List.last(sorted)}"
  end

  defp add_if(list, true, message), do: list ++ [message]
  defp add_if(list, false, _message), do: list
end
