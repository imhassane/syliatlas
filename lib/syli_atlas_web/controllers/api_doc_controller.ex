defmodule SyliAtlasWeb.ApiDocController do
  @moduledoc """
  The public API's documentation page, `/fr/api` and `/en/api`: what the API
  holds, every route with real answers, code in four languages, the limits,
  the errors, and the server time of each route measured every hour.

  Its validator follows the code, the data and the hour (the measures change
  every hour), so browsers get a 304 until one of them changes.
  """
  use SyliAtlasWeb, :controller

  alias SyliAtlas.{ApiTimings, Sources}
  alias SyliAtlasWeb.{ApiDoc, Paths, Seo}

  plug :put_layout, false

  def show(conn, _params) do
    locale = conn.assigns.locale
    now = DateTime.utc_now()
    etag = ~s(W/"#{:erlang.phash2({SyliAtlasWeb.Build.version(), ApiTimings.hour(now), locale})}")

    conn =
      conn
      |> put_resp_header("cache-control", "public, no-cache")
      |> put_resp_header("etag", etag)

    if etag in get_req_header(conn, "if-none-match") do
      send_resp(conn, 304, "")
    else
      render_page(conn, locale, now)
    end
  end

  defp render_page(conn, locale, now) do
    paths = %{"fr" => Paths.api("fr"), "en" => Paths.api("en")}
    timings = ApiTimings.last_day(now)
    budget = ApiTimings.budget_us()

    routes =
      for r <- ApiDoc.routes(locale) do
        Map.put(r, :perf, perf(timings[r.id], budget))
      end

    conn
    |> put_view(SyliAtlasWeb.ApiDocHTML)
    |> render(:show,
      page_title: gettext("Public API"),
      seo:
        Seo.page(
          locale,
          paths,
          if(locale == "fr",
            do:
              "L'API publique de Syli Atlas : indicateurs économiques des 54 pays africains en JSON et CSV, gratuitement, sans clé, avec la source de chaque chiffre.",
            else:
              "The Syli Atlas public API: economic indicators of the 54 African countries in JSON and CSV, free, without a key, with the source of every figure."
          )
        ),
      alternates: Seo.alternates_for_header(paths),
      routes: routes,
      measured?: Enum.any?(routes, & &1.perf),
      last_measure:
        timings |> Map.values() |> Enum.map(& &1.last) |> Enum.max(DateTime, fn -> nil end),
      budget_ms: div(budget, 1000),
      rate_limit: rate_limit(),
      edition: Sources.published_edition("imf_weo"),
      base_url: SyliAtlasWeb.Endpoint.url() <> "/api/v1",
      error_example: ApiDoc.error_example(locale),
      indicators: ApiDoc.indicators(locale),
      value_lists: ApiDoc.value_lists(locale),
      shared_schemas: ApiDoc.shared_schemas(locale)
    )
  end

  # The day of one route, ready to draw: p50, p95, p99 (ms), the budget
  # verdict, and a sparkline of the hourly p95 against the budget.
  defp perf(nil, _budget), do: nil

  defp perf(%{hours: hours, p50: p50, p95: p95, p99: p99}, budget) do
    values = Enum.map(hours, & &1.p95_us)
    top = max(budget * 1.25, Enum.max(values) * 1.1)
    y = fn v -> Float.round(26 - v / top * 24, 1) end
    step = if length(values) > 1, do: 120 / (length(values) - 1), else: 0.0

    points =
      values
      |> Enum.with_index()
      |> Enum.map_join(" ", fn {v, i} -> "#{Float.round(i * step * 1.0, 1)},#{y.(v)}" end)

    %{
      p50: p50,
      p95: p95,
      p99: p99,
      ok?: p99 <= budget,
      hours: length(hours),
      points:
        if(length(values) == 1, do: "0,#{y.(hd(values))} 120,#{y.(hd(values))}", else: points),
      budget_y: y.(budget)
    }
  end

  defp rate_limit,
    do: Application.get_env(:syli_atlas, SyliAtlasWeb.Plugs.ApiRateLimit, [])[:public] || 60
end
