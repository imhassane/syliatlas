defmodule SyliAtlas.Imports.ImfClient do
  @moduledoc """
  Reads the IMF DataMapper API, which publishes the World Economic Outlook.

  `fetch_label/0` is cheap and runs every morning; `fetch_values/0` runs
  only when a new edition appears.
  """
  alias SyliAtlas.Sources.Indicators

  @base "https://www.imf.org/external/datamapper/api/v1"

  @doc "Returns the edition label, e.g. \"World Economic Outlook (October 2026)\"."
  def fetch_label do
    with {:ok, %{"indicators" => indicators}} <- get("/indicators"),
         %{"source" => source} <- indicators["NGDP_RPCH"] do
      {:ok, source}
    else
      {:error, _} = error -> error
      _ -> {:error, :unexpected_response}
    end
  end

  @doc "Returns %{\"values\" => %{imf_code => %{area => %{year => value}}}}."
  def fetch_values do
    Indicators.all()
    |> Enum.reduce_while({:ok, %{}}, fn %{imf: code}, {:ok, acc} ->
      case get("/" <> code) do
        {:ok, %{"values" => %{^code => values}}} -> {:cont, {:ok, Map.put(acc, code, values)}}
        {:ok, _} -> {:halt, {:error, {:unexpected_response, code}}}
        {:error, reason} -> {:halt, {:error, {reason, code}}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, %{"values" => values}}
      error -> error
    end
  end

  defp get(path) do
    options = Application.get_env(:syli_atlas, __MODULE__, [])

    [
      base_url: Keyword.get(options, :base_url, @base),
      url: path,
      retry: :transient,
      receive_timeout: 30_000
    ]
    |> Keyword.merge(Keyword.get(options, :req_options, []))
    |> Req.request()
    |> case do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, exception} -> {:error, Exception.message(exception)}
    end
  end
end
