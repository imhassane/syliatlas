defmodule SyliAtlasWeb.WebAnalyticsTest do
  @moduledoc "Cloudflare Web Analytics: only with its token, never in the framed views."
  use SyliAtlasWeb.ConnCase, async: false

  alias SyliAtlasWeb.{CSP, WebAnalytics}

  @embed "/embed/fr/pays/cote-d-ivoire/real_gdp_index?from=2020&to=2025"

  setup do
    SyliAtlas.Fixtures.load_snapshot!()

    previous =
      {Application.get_env(:syli_atlas, CSP), Application.get_env(:syli_atlas, WebAnalytics)}

    Application.put_env(:syli_atlas, CSP, mode: :report_only)

    on_exit(fn ->
      {csp, analytics} = previous
      Application.put_env(:syli_atlas, CSP, csp || [])
      Application.put_env(:syli_atlas, WebAnalytics, analytics || [])
    end)

    :ok
  end

  defp token(value), do: Application.put_env(:syli_atlas, WebAnalytics, token: value)

  defp page(path) do
    conn = get(build_conn(), path)
    [policy] = get_resp_header(conn, "content-security-policy-report-only")
    {html_response(conn, 200), policy}
  end

  test "without a token: no beacon, the policy is unchanged" do
    token(nil)
    {html, policy} = page("/fr/pays/senegal")

    refute html =~ "cf-web-analytics"
    refute policy =~ "cloudflareinsights"
  end

  test "with a token: the pages carry it and the policy allows the beacon" do
    token("abc123")

    for path <- ["/en", "/fr/pays/senegal", "/fr/connexion"] do
      {html, policy} = page(path)

      assert html =~ ~s(<meta name="cf-web-analytics" content="abc123">)
      assert policy =~ "script-src 'self' "
      assert policy =~ ~r/script-src [^;]*https:\/\/static\.cloudflareinsights\.com/
      assert policy =~ ~r/connect-src [^;]*https:\/\/cloudflareinsights\.com/
    end
  end

  test "with a token, the framed views stay without tracking" do
    token("abc123")
    {html, policy} = page(@embed)

    refute html =~ "cf-web-analytics"
    refute html =~ "cloudflareinsights"
    refute policy =~ "cloudflareinsights"
  end
end
