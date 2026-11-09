defmodule SyliAtlasWeb.ApiControllerTest do
  use SyliAtlasWeb.ConnCase, async: false

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    :ok
  end

  test "area profile with a reference year", %{conn: conn} do
    body = conn |> get(~p"/api/v1/areas/CIV?from=2015&to=2025") |> json_response(200)
    assert body["period"]["changes"]["real_gdp_index"] == 77.8
  end

  test "rejects an impossible period", %{conn: conn} do
    assert %{"error" => _} =
             conn |> get(~p"/api/v1/areas/CIV?from=2025&to=2020") |> json_response(400)

    assert %{"error" => _} = conn |> get(~p"/api/v1/areas/CIV?from=1990") |> json_response(400)
  end

  test "unknown area", %{conn: conn} do
    assert conn |> get(~p"/api/v1/areas/XXX") |> json_response(404)
  end

  test "compare and ranking", %{conn: conn} do
    assert [%{"code" => "CIV"}, %{"code" => "GHA"}] =
             conn |> get(~p"/api/v1/compare?codes=CIV,GHA") |> json_response(200)

    assert [%{"code" => "CPV"} | _] =
             conn |> get(~p"/api/v1/ranking?region=west_africa") |> json_response(200)
  end

  test "cache headers and 304", %{conn: conn} do
    first = get(conn, ~p"/api/v1/areas/CIV")
    [etag] = get_resp_header(first, "etag")

    assert get_resp_header(first, "cache-control") == [
             "public, max-age=3600, stale-while-revalidate=86400"
           ]

    second = build_conn() |> put_req_header("if-none-match", etag) |> get(~p"/api/v1/areas/CIV")
    assert second.status == 304
  end

  test "csv export", %{conn: conn} do
    body = conn |> get(~p"/api/v1/areas/CIV/csv") |> response(200)
    assert body =~ "year,status,real_gdp_index"
    assert body =~ "2026,projection"
  end

  test "version for the service worker", %{conn: conn} do
    assert %{"edition" => %{"id" => "2026-10"}} =
             conn |> get(~p"/api/v1/version") |> json_response(200)
  end
end
