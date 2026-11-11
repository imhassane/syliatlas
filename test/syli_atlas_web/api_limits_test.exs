defmodule SyliAtlasWeb.ApiLimitsTest do
  @moduledoc "Requests per minute, the error shape, Server-Timing, the table of contents."
  use SyliAtlasWeb.ConnCase, async: false

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    previous = Application.get_env(:syli_atlas, SyliAtlasWeb.Plugs.ApiRateLimit)
    on_exit(fn -> Application.put_env(:syli_atlas, SyliAtlasWeb.Plugs.ApiRateLimit, previous) end)
    :ok
  end

  defp limit(public, internal) do
    Application.put_env(:syli_atlas, SyliAtlasWeb.Plugs.ApiRateLimit,
      enabled: true,
      public: public,
      internal: internal
    )
  end

  defp from(ip), do: build_conn() |> put_req_header("x-real-ip", ip)

  test "beyond the limit: 429, retry-after and the usual error" do
    limit(3, 100)
    ip = "196.1.1.#{System.unique_integer([:positive]) |> rem(250)}"

    for left <- [2, 1, 0] do
      conn = ip |> from() |> get(~p"/api/v1/areas")
      assert conn.status == 200
      assert get_resp_header(conn, "ratelimit-limit") == ["3"]
      assert get_resp_header(conn, "ratelimit-remaining") == [Integer.to_string(left)]
    end

    conn = ip |> from() |> get(~p"/api/v1/areas")
    assert conn.status == 429
    assert [seconds] = get_resp_header(conn, "retry-after")
    assert String.to_integer(seconds) in 1..60
    assert %{"error" => %{"code" => "rate_limited", "docs" => docs}} = json_response(conn, 429)
    assert docs =~ "/api#errors"

    # Another visitor is not affected.
    assert "196.2.2.2" |> from() |> get(~p"/api/v1/areas") |> json_response(200)
  end

  test "the site's own calls have their own counter" do
    limit(1, 100)
    ip = "196.3.3.#{System.unique_integer([:positive]) |> rem(250)}"

    assert ip |> from() |> get(~p"/api/v1/areas") |> json_response(200)
    assert ip |> from() |> get(~p"/api/v1/areas") |> json_response(429)
    assert ip |> from() |> get(~p"/api/v1/search?q=senegal") |> json_response(200)
  end

  test "errors have a stable code", %{conn: conn} do
    assert %{"error" => %{"code" => "unknown_area", "message" => _}} =
             conn |> get(~p"/api/v1/areas/XXX") |> json_response(404)

    assert %{"error" => %{"code" => "invalid_period"}} =
             build_conn() |> get(~p"/api/v1/areas/CIV?from=1990") |> json_response(400)

    assert %{"error" => %{"code" => "codes_required"}} =
             build_conn() |> get(~p"/api/v1/compare") |> json_response(400)

    assert %{"error" => %{"code" => "unknown_indicator"}} =
             build_conn() |> get(~p"/api/v1/ranking?indicator=nope") |> json_response(400)

    assert %{"error" => %{"code" => "not_found", "docs" => docs}} =
             build_conn() |> get("/api/v1/nothing/here?locale=fr") |> json_response(404)

    assert docs =~ "/fr/api#erreurs"
  end

  test "the table of contents at /api/v1", %{conn: conn} do
    body = conn |> get(~p"/api/v1") |> json_response(200)
    assert body["docs"]["fr"] =~ "/fr/api"
    assert body["routes"]["area"] == "/api/v1/areas/{code}?from=&to="
    assert body["data"]["edition"] == "2026-10"
    assert body["limits"]["requests_per_minute"] > 0
  end

  test "every answer gives its server time", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/areas/CIV")
    assert [timing] = get_resp_header(conn, "server-timing")
    assert timing =~ ~r/^app;desc="Syli Atlas";dur=\d+\.\d\d$/
  end
end
