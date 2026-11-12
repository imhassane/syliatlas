defmodule SyliAtlas.Budgets.Imf do
  @moduledoc """
  Revenue and expenditure of the general government, in % of GDP, for the
  54 countries: IMF, Fiscal Monitor (DataMapper series `GGR_G01_GDP_PT` and
  `G_X_G01_GDP_PT`). It is the floor every country has, before any budget
  law is collected: a model of the IMF, not the law the country voted.

  The bundled file is `priv/data/imf_fiscal_monitor.json` (`mix
  budgets.refresh_imf` fetches it again). Kept in memory.
  """

  @key {__MODULE__, :document}
  @base "https://www.imf.org/external/datamapper/api/v1"
  @series %{"revenue" => "GGR_G01_GDP_PT", "expenditure" => "G_X_G01_GDP_PT"}
  @first_year 2015
  @last_year 2030

  def path, do: Application.app_dir(:syli_atlas, "priv/data/imf_fiscal_monitor.json")

  def document do
    case :persistent_term.get(@key, nil) do
      nil ->
        doc =
          if File.exists?(path()),
            do: path() |> File.read!() |> Jason.decode!(),
            else: %{"countries" => %{}, "source" => %{}}

        :persistent_term.put(@key, doc)
        doc

      doc ->
        doc
    end
  end

  def reload!, do: :persistent_term.erase(@key)

  @doc "`%{\"revenue\" => %{\"2026\" => 18.98, …}, \"expenditure\" => …}` or nil."
  def for_country(code), do: document()["countries"][code]

  @doc "The value of a series for a year, as a float, or nil."
  def at(nil, _series, _year), do: nil
  def at(entry, series, year), do: get_in(entry, [series, Integer.to_string(year)])

  @doc """
  Fetches both series from the IMF and returns the document (not written).
  `countries` are the area codes to keep (their IMF code is the same).
  """
  def fetch(countries) do
    with {:ok, label} <- label(),
         {:ok, values} <- values() do
      {:ok,
       %{
         "source" => %{
           "name" => "IMF, Fiscal Monitor",
           "label" => label,
           "url" => "https://www.imf.org/external/datamapper/GGR_G01_GDP_PT@FM"
         },
         "fetched_at" =>
           DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
         "series" => @series,
         "countries" =>
           Map.new(countries, fn code ->
             {code,
              Map.new(@series, fn {key, imf} ->
                {key, years(get_in(values, [imf, code]) || %{})}
              end)}
           end)
       }}
    end
  end

  defp years(by_year) do
    for year <- @first_year..@last_year,
        y = Integer.to_string(year),
        v = by_year[y],
        is_number(v),
        into: %{},
        do: {y, Float.round(v * 1.0, 2)}
  end

  defp label do
    case get("/indicators") do
      {:ok, %{"indicators" => %{"GGR_G01_GDP_PT" => %{"source" => source}}}} -> {:ok, source}
      {:ok, _} -> {:error, :unexpected_response}
      error -> error
    end
  end

  defp values do
    Enum.reduce_while(@series, {:ok, %{}}, fn {_key, imf}, {:ok, acc} ->
      case get("/" <> imf) do
        {:ok, %{"values" => %{^imf => v}}} -> {:cont, {:ok, Map.put(acc, imf, v)}}
        {:ok, _} -> {:halt, {:error, {:unexpected_response, imf}}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp get(path) do
    options = Application.get_env(:syli_atlas, __MODULE__, [])

    [base_url: @base, url: path, retry: :transient, receive_timeout: 30_000]
    |> Keyword.merge(Keyword.get(options, :req_options, []))
    |> Req.request()
    |> case do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, exception} -> {:error, Exception.message(exception)}
    end
  end
end
