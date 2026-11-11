defmodule SyliAtlasWeb.Api.ApiController do
  @moduledoc """
  Public API v1. Answers are built by `SyliAtlasWeb.Api.V1` and described
  field by field in `SyliAtlasWeb.Api.Spec` (`/api/v1/openapi.json`).
  Documentation: `/fr/api`, `/en/api`.
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Geo
  alias SyliAtlas.Profiles.Queries
  alias SyliAtlas.Sources.Indicators
  alias SyliAtlasWeb.Api.{Catalog, Errors, Params, Spec, V1}
  alias SyliAtlasWeb.Paths

  @doc "The table of contents: routes, documentation, closed lists of values."
  def index(conn, _params) do
    base = SyliAtlasWeb.Endpoint.url()

    send_json(
      conn,
      %{
        name: "Syli Atlas API",
        version: "v1",
        docs: %{fr: base <> Paths.api("fr"), en: base <> Paths.api("en")},
        openapi: base <> "/api/v1/openapi.json",
        routes: %{
          areas: "/api/v1/areas",
          area: "/api/v1/areas/{code}?from=&to=",
          csv: "/api/v1/areas/{code}/csv",
          compare: "/api/v1/compare?codes=&from=&to=",
          ranking: "/api/v1/ranking?indicator=&mode=&region=&from=&to=",
          indicators: "/api/v1/indicators"
        },
        values: %{
          kind: Catalog.kinds(),
          region: Catalog.regions(),
          status: Catalog.statuses(),
          unit: Catalog.units(),
          mode: Catalog.modes()
        },
        limits: %{requests_per_minute: rate_limit(), cache_seconds: 3600}
      },
      "Index"
    )
  end

  @doc "The OpenAPI 3.1 description."
  def openapi(conn, _params), do: send_json(conn, Spec.document())

  @doc "Any other address under /api/v1."
  def not_found(conn, _params),
    do: error(conn, 404, "not_found", "No such route: see the documentation")

  def areas(conn, _params), do: send_json(conn, V1.areas(), "AreaList")

  def area(conn, %{"code" => code} = params) do
    with {:ok, from, to} <- Params.period(params),
         {:ok, answer} <- V1.area(code, from, to) do
      send_json(conn, answer, "AreaAnswer")
    else
      :not_found -> error(conn, 404, "unknown_area", "Unknown area: #{code}")
      {:error, message} -> error(conn, 400, "invalid_period", message)
    end
  end

  def compare(conn, params) do
    with codes when codes != [] <- Params.codes(params["codes"]),
         {:ok, from, to} <- Params.period(params) do
      send_json(conn, V1.compare(codes, from, to), "CompareAnswer")
    else
      [] -> error(conn, 400, "codes_required", "codes is required, e.g. codes=CIV,GHA")
      {:error, message} -> error(conn, 400, "invalid_period", message)
    end
  end

  def ranking(conn, params) do
    indicator = params["indicator"] || "real_gdp_index"
    region = if params["region"] in Geo.regions(), do: params["region"]
    mode = if params["mode"] == "value", do: "value", else: "change"

    with true <- Indicators.valid?(indicator) || {:unknown_indicator, indicator},
         {:ok, from, to} <- Params.period(params) do
      send_json(conn, V1.ranking(indicator, mode, region, from, to), "RankingAnswer")
    else
      {:unknown_indicator, name} ->
        error(conn, 400, "unknown_indicator", "Unknown indicator: #{name}")

      {:error, message} ->
        error(conn, 400, "invalid_period", message)
    end
  end

  def indicators(conn, _params), do: send_json(conn, V1.indicators(), "IndicatorList")

  @doc "One area as CSV: one row per year, one column per indicator."
  def csv(conn, %{"code" => code}) do
    case Queries.area_profile(code, 2020, 2025) do
      nil ->
        error(conn, 404, "unknown_area", "Unknown area: #{code}")

      json ->
        %{"profile" => profile} = Jason.decode!(json)
        keys = Catalog.indicator_keys()

        rows =
          Indicators.years()
          |> Enum.with_index()
          |> Enum.map(fn {year, i} ->
            status =
              Indicators.status_for(year, %{
                estimate_from: profile["years"]["estimate_from"],
                projection_from: profile["years"]["projection_from"]
              })

            [year, status | Enum.map(keys, &Enum.at(profile["series"][&1] || [], i))]
          end)

        body =
          [["year", "status" | keys] | rows]
          |> Enum.map_join("\n", fn row -> Enum.map_join(row, ",", &csv_cell/1) end)

        source =
          "# Source: IMF #{profile["edition"]["label"]}, via Syli Atlas" <>
            " · Syli Atlas calculations: CC BY 4.0 (#{SyliAtlasWeb.Seo.license_url()})\n"

        conn
        |> put_resp_content_type("text/csv")
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_header(
          "content-disposition",
          ~s(attachment; filename="syli-atlas-#{profile["slug"]["en"]}.csv")
        )
        |> send_resp(200, source <> body <> "\n")
    end
  end

  defp csv_cell(nil), do: ""
  defp csv_cell(v), do: to_string(v)

  # Answers in the documented key order (see Spec.ordered/2).
  defp send_json(conn, body, schema), do: send_json(conn, Spec.ordered(body, schema))

  defp send_json(conn, body) do
    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("access-control-allow-origin", "*")
    |> send_resp(200, Jason.encode_to_iodata!(body))
  end

  defp rate_limit,
    do: Application.get_env(:syli_atlas, SyliAtlasWeb.Plugs.ApiRateLimit, [])[:public] || 60

  defp error(conn, status, code, message), do: Errors.send(conn, status, code, message)
end
