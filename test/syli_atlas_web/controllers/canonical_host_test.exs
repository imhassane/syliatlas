defmodule SyliAtlasWeb.CanonicalHostTest do
  use SyliAtlasWeb.ConnCase, async: false

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    previous = Application.get_env(:syli_atlas, :site)
    on_exit(fn -> restore(previous) end)
    :ok
  end

  defp restore(nil), do: Application.delete_env(:syli_atlas, :site)
  defp restore(value), do: Application.put_env(:syli_atlas, :site, value)

  defp on_host(conn, host), do: %{conn | host: host}

  describe "canonical host (production)" do
    setup do
      Application.put_env(:syli_atlas, :site, canonical_redirect: true, noindex: false)
      :ok
    end

    test "the Railway address sends readers and crawlers to the domain, path and query kept",
         %{conn: conn} do
      conn = conn |> on_host("syliatlas.up.railway.app") |> get("/fr/pays/senegal?from=2020")
      assert conn.status == 301

      assert get_resp_header(conn, "location") == [
               "https://#{SyliAtlasWeb.Endpoint.host()}/fr/pays/senegal?from=2020"
             ]
    end

    test "a form sent to the old host keeps its method (308)", %{conn: conn} do
      conn = conn |> on_host("syliatlas.up.railway.app") |> post("/fr/connexion", %{})
      assert conn.status == 308
    end

    test "the health check answers on any host", %{conn: conn} do
      assert conn |> on_host("healthcheck.railway.app") |> get("/health") |> text_response(200)
    end

    test "the canonical host is served", %{conn: conn} do
      conn = conn |> on_host(SyliAtlasWeb.Endpoint.host()) |> get("/fr")
      assert conn.status == 200
    end
  end

  describe "development copy (SITE_NOINDEX)" do
    setup do
      Application.put_env(:syli_atlas, :site, canonical_redirect: false, noindex: true)
      :ok
    end

    test "every response asks search engines not to index", %{conn: conn} do
      conn = get(conn, "/fr")
      assert get_resp_header(conn, "x-robots-tag") == ["noindex, nofollow"]
    end

    test "robots.txt disallows everything and names no sitemap", %{conn: conn} do
      txt = conn |> get("/robots.txt") |> response(200)
      assert txt =~ "Disallow: /\n"
      refute txt =~ "Sitemap:"
    end
  end

  test "production pages carry no noindex header", %{conn: conn} do
    Application.put_env(:syli_atlas, :site, canonical_redirect: false, noindex: false)
    assert conn |> get("/fr") |> get_resp_header("x-robots-tag") == []
  end

  test "the home page describes the site and its search box", %{conn: conn} do
    html = conn |> get("/fr") |> html_response(200)
    assert html =~ ~s("@type":"WebSite")
    assert html =~ ~s("@type":"Organization")
    assert html =~ "search_term_string"
  end
end
