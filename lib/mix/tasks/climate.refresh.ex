defmodule Mix.Tasks.Climate.Refresh do
  @shortdoc "Updates the WGI scores of priv/data/business_climate.json from the World Bank API"
  @moduledoc """
  Fetches the latest Worldwide Governance Indicators scores (0-100) of the
  54 countries from api.worldbank.org and rewrites the WGI part of
  `priv/data/business_climate.json`. B-READY scores come from the report's
  tables and are updated by hand at each edition.

      mix climate.refresh
  """
  use Mix.Task

  @indicators %{
    "regulatory_quality" => "GOV_WGI_RQ.SC",
    "rule_of_law" => "GOV_WGI_RL.SC",
    "government_effectiveness" => "GOV_WGI_GE.SC",
    "control_of_corruption" => "GOV_WGI_CC.SC"
  }

  @impl Mix.Task
  def run(_args) do
    Application.ensure_all_started(:req)
    path = "priv/data/business_climate.json"
    file = path |> File.read!() |> Jason.decode!()
    codes = Map.keys(file["countries"])

    {scores, years} =
      Enum.reduce(@indicators, {%{}, MapSet.new()}, fn {key, id}, {acc, years} ->
        url =
          "https://api.worldbank.org/v2/country/#{Enum.join(codes, ";")}/indicator/#{id}" <>
            "?format=json&source=3&mrnev=1&per_page=500"

        [_meta, rows] = Req.get!(url).body

        Enum.reduce(rows, {acc, years}, fn
          %{"value" => nil}, a ->
            a

          %{"countryiso3code" => code, "value" => v, "date" => year}, {acc, years} ->
            {put_in(acc, [Access.key(code, %{}), key], Float.round(v / 1, 1)),
             MapSet.put(years, year)}
        end)
      end)

    countries =
      Map.new(file["countries"], fn {code, e} ->
        wgi = scores[code]

        {code,
         if(wgi && map_size(wgi) == 4, do: Map.put(e, "wgi", wgi), else: Map.delete(e, "wgi"))}
      end)

    year = years |> Enum.max() |> String.to_integer()

    file
    |> Map.put("countries", countries)
    |> put_in(["sources", "wgi", "year"], year)
    |> Map.put("as_of", Date.to_iso8601(Date.utc_today()))
    |> Jason.encode!(pretty: true)
    |> then(&File.write!(path, &1))

    Mix.shell().info("WGI #{year}: #{Enum.count(countries, fn {_, e} -> e["wgi"] end)} countries")
  end
end
