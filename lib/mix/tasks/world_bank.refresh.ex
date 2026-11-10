defmodule Mix.Tasks.WorldBank.Refresh do
  @shortdoc "Updates priv/data/world_bank.json from the World Bank API"
  @moduledoc """
  Fetches the series listed in `SyliAtlas.WorldBank` for the 54 countries,
  2015 onwards, from api.worldbank.org, and rewrites
  `priv/data/world_bank.json` with each database's last update date.

      mix world_bank.refresh

  WDI series are read one by one from the indicator API; IDS series from the
  sources API (database 6), which also gives the debt owed to one creditor
  country (counterpart area 730: China).
  """
  use Mix.Task

  @base "https://api.worldbank.org/v2"

  @impl Mix.Task
  def run(_args) do
    Application.ensure_all_started(:req)
    path = "priv/data/world_bank.json"

    countries =
      "priv/data/areas.json"
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("areas")
      |> Enum.filter(&(&1["kind"] == "country"))
      |> Enum.map(& &1["code"])

    years = Enum.to_list(SyliAtlas.WorldBank.first_year()..SyliAtlas.WorldBank.last_year())

    {values, updated} =
      Enum.reduce(SyliAtlas.WorldBank.series(), {%{}, %{}}, fn {key, code, db, _origin},
                                                               {acc, updated} ->
        {rows, last_updated} = fetch(code, db, countries, years)
        Mix.shell().info("#{key} (#{code}): #{length(rows)} values, updated #{last_updated}")
        name = if match?({:ids, _}, db) or db == :ids, do: "ids", else: "wdi"

        acc =
          Enum.reduce(rows, acc, fn {country, year, v}, acc ->
            put_in(acc, [Access.key(country, %{}), Access.key(key, %{}), year], round_value(v))
          end)

        {acc, Map.update(updated, name, last_updated, &max(&1, last_updated || ""))}
      end)

    file = %{
      "as_of" => Date.to_iso8601(Date.utc_today()),
      "sources" => %{
        "ids" => %{
          "name" => "World Bank, International Debt Statistics",
          "url" => "https://datacatalog.worldbank.org/search/dataset/0038015",
          "license" => "CC BY 4.0",
          "last_updated" => updated["ids"]
        },
        "wdi" => %{
          "name" => "World Bank, World Development Indicators",
          "url" => "https://datacatalog.worldbank.org/search/dataset/0037712",
          "license" => "CC BY 4.0",
          "last_updated" => updated["wdi"]
        }
      },
      "countries" => Map.new(countries, &{&1, Map.get(values, &1, %{})})
    }

    File.write!(path, Jason.encode!(file, pretty: true))
    Mix.shell().info("#{path}: #{map_size(values)} countries with data")
  end

  defp fetch(code, :wdi, countries, years) do
    url =
      "#{@base}/country/#{Enum.join(countries, ";")}/indicator/#{code}" <>
        "?format=json&source=2&per_page=2000&date=#{hd(years)}:#{List.last(years)}"

    case get(url) do
      [%{"lastupdated" => updated}, rows] when is_list(rows) ->
        {for(
           %{"countryiso3code" => c, "date" => y, "value" => v} <- rows,
           is_number(v),
           do: {c, y, v}
         ), updated}

      _ ->
        {[], nil}
    end
  end

  defp fetch(code, :ids, countries, years), do: fetch(code, {:ids, "WLD"}, countries, years)

  defp fetch(code, {:ids, counterpart}, countries, years) do
    time = Enum.map_join(years, ";", &"YR#{&1}")

    url =
      "#{@base}/sources/6/country/#{Enum.join(countries, ";")}/series/#{code}" <>
        "/counterpart-area/#{counterpart}/time/#{time}?format=json&per_page=5000"

    case get(url) do
      %{"lastupdated" => updated, "source" => %{"data" => data}} ->
        {for(
           %{"variable" => vars, "value" => v} <- data,
           is_number(v),
           c = var(vars, "Country"),
           "YR" <> y = var(vars, "Time"),
           do: {c, y, v}
         ), updated}

      _ ->
        {[], nil}
    end
  end

  defp var(vars, concept), do: Enum.find_value(vars, &(&1["concept"] == concept && &1["id"]))

  # The API sometimes answers an HTML error page with status 200: retried too.
  defp get(url, attempts \\ 4) do
    result =
      case Req.get(url, retry: :transient, max_retries: 4, receive_timeout: 120_000) do
        {:ok, %{status: 200, body: body}} when is_binary(body) -> Jason.decode(body)
        {:ok, %{status: 200, body: body}} -> {:ok, body}
        other -> {:error, other}
      end

    case result do
      {:ok, body} ->
        body

      {:error, _} when attempts > 1 ->
        Process.sleep(2_000)
        get(url, attempts - 1)

      {:error, reason} ->
        Mix.raise("World Bank API: #{inspect(reason, limit: 5)} for #{url}")
    end
  end

  defp round_value(v) when abs(v) >= 1000, do: round(v)
  defp round_value(v), do: Float.round(v * 1.0, 3)
end
