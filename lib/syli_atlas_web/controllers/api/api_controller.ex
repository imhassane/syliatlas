defmodule SyliAtlasWeb.Api.ApiController do
  @moduledoc """
  Public JSON API. Answers come straight from the JSON functions, as text,
  without decoding and re-encoding.
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.{Geo, Profiles, Sources}
  alias SyliAtlas.Profiles.Queries
  alias SyliAtlas.Sources.Indicators
  alias SyliAtlasWeb.Api.{Errors, Params}
  alias SyliAtlasWeb.Paths

  @doc "The table of contents: routes, documentation, data edition."
  def index(conn, _params) do
    base = SyliAtlasWeb.Endpoint.url()
    edition = Sources.published_edition("imf_weo")

    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> json(%{
      name: "Syli Atlas API",
      version: "v1",
      docs: %{fr: base <> Paths.api("fr"), en: base <> Paths.api("en")},
      routes: %{
        areas: "/api/v1/areas",
        area: "/api/v1/areas/{code}?from=&to=",
        csv: "/api/v1/areas/{code}/csv",
        compare: "/api/v1/compare?codes=&from=&to=",
        ranking: "/api/v1/ranking?indicator=&mode=&region=&from=&to=&locale="
      },
      data: %{
        source: "IMF World Economic Outlook",
        edition: edition && edition.code,
        label: edition && edition.label
      },
      licence: "Each figure keeps the licence of its source: cite it as the documentation says.",
      limits: %{requests_per_minute: rate_limit(), cache_seconds: 3600}
    })
  end

  @doc "Any other address under /api/v1."
  def not_found(conn, _params),
    do: error(conn, 404, "not_found", "No such route: see the documentation")

  defp rate_limit,
    do: Application.get_env(:syli_atlas, SyliAtlasWeb.Plugs.ApiRateLimit, [])[:public] || 60

  def areas(conn, _params) do
    areas =
      Enum.map(Geo.list_areas(), fn a ->
        %{
          code: a.code,
          kind: a.kind,
          region: a.region_code,
          name: %{fr: a.name_fr, en: a.name_en},
          slug: %{fr: a.slug_fr, en: a.slug_en}
        }
      end)

    json(conn, %{areas: areas})
  end

  def area(conn, %{"code" => code} = params) do
    with {:ok, from, to} <- Params.period(params),
         json when is_binary(json) <- Queries.area_profile(code, from, to) do
      raw(conn, json)
    else
      nil -> error(conn, 404, "unknown_area", "Unknown area: #{code}")
      {:error, message} -> error(conn, 400, "invalid_period", message)
    end
  end

  def compare(conn, params) do
    with codes when codes != [] <- Params.codes(params["codes"]),
         {:ok, from, to} <- Params.period(params) do
      raw(conn, Queries.compare(codes, from, to))
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
      raw(
        conn,
        Queries.ranking(indicator, from, to,
          region: region,
          mode: mode,
          locale: Params.locale(params)
        )
      )
    else
      {:unknown_indicator, name} ->
        error(conn, 400, "unknown_indicator", "Unknown indicator: #{name}")

      {:error, message} ->
        error(conn, 400, "invalid_period", message)
    end
  end

  @doc """
  Site search: grouped results and, when the query names a country and a
  theme (« dette sénégal »), the figure itself. Same engine as the search
  page (`SyliAtlasWeb.Search`), used by the suggestions under the field.
  """
  def search(conn, params) do
    locale = Params.locale(params)
    Gettext.put_locale(SyliAtlasWeb.Gettext, locale)
    json(conn, SyliAtlasWeb.Search.run(params["q"] || "", locale))
  end

  def version(conn, _params) do
    edition = Sources.published_edition("imf_weo")

    conn
    |> put_resp_header("cache-control", "no-cache")
    |> json(%{
      version: Profiles.data_version(),
      build: SyliAtlasWeb.Build.id(),
      page_version: SyliAtlasWeb.Build.version(),
      edition:
        edition &&
          %{
            source: "imf_weo",
            id: edition.code,
            label: edition.label,
            published_at: edition.published_at
          }
    })
  end

  @doc "Paths of the pages to save for offline reading, in one language."
  def offline_pages(conn, params) do
    json(conn, %{pages: SyliAtlasWeb.OfflinePages.list(Params.locale(params))})
  end

  def offline_pack(conn, _params), do: raw(conn, Queries.offline_pack())

  @doc "One area as CSV: one row per year, one column per indicator."
  def csv(conn, %{"code" => code}) do
    case Queries.area_profile(code, 2020, 2025) do
      nil ->
        error(conn, 404, "unknown_area", "Unknown area: #{code}")

      json ->
        %{"profile" => profile} = Jason.decode!(json)
        keys = Indicators.published_keys()

        rows =
          Indicators.years()
          |> Enum.with_index()
          |> Enum.map(fn {year, i} ->
            status =
              Indicators.status_for(year, %{
                estimate_from: profile["years"]["estimate_from"],
                projection_from: profile["years"]["projection_from"]
              })

            [year, status | Enum.map(keys, &Enum.at(profile["series"][&1], i))]
          end)

        body =
          [["year", "status" | keys] | rows]
          |> Enum.map_join("\n", fn row -> Enum.map_join(row, ",", &csv_cell/1) end)

        source = "# Source: IMF #{profile["edition"]["label"]}, via Syli Atlas\n"

        conn
        |> put_resp_content_type("text/csv")
        |> put_resp_header(
          "content-disposition",
          ~s(attachment; filename="syli-atlas-#{profile["slug"]["en"]}.csv")
        )
        |> send_resp(200, source <> body <> "\n")
    end
  end

  defp csv_cell(nil), do: ""
  defp csv_cell(v), do: to_string(v)

  defp raw(conn, json) do
    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("access-control-allow-origin", "*")
    |> send_resp(200, json || "null")
  end

  defp error(conn, status, code, message), do: Errors.send(conn, status, code, message)
end
