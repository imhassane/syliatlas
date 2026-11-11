defmodule SyliAtlasWeb.CSPTest do
  @moduledoc "Content-Security-Policy of HTML pages and the violation reports."
  use SyliAtlasWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias SyliAtlasWeb.CSP

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    previous = Application.get_env(:syli_atlas, CSP)
    on_exit(fn -> Application.put_env(:syli_atlas, CSP, previous || []) end)
    :ok
  end

  defp mode(mode), do: Application.put_env(:syli_atlas, CSP, mode: mode)

  # The scripts a browser runs: no src, and a JavaScript type (or none), or
  # speculation rules. JSON and JSON-LD blocks are data. Read from the raw
  # HTML: the browser hashes the exact bytes, whitespace included.
  defp inline_scripts(html) do
    ~r{<script(\s[^>]*)?>(.*?)</script>}s
    |> Regex.scan(html, capture: :all_but_first)
    |> Enum.flat_map(fn
      [attrs, body] -> if runs?(attrs), do: [body], else: []
      [body] -> [body]
    end)
  end

  defp runs?(attrs) do
    not (attrs =~ ~r/\ssrc=/) and
      case Regex.run(~r/\stype="([^"]*)"/, attrs) do
        nil -> true
        [_, type] -> type in ["", "text/javascript", "module", "speculationrules"]
      end
  end

  defp sha256(text), do: "'sha256-#{Base.encode64(:crypto.hash(:sha256, text))}'"

  for path <- ["/en", "/fr/pays/senegal", "/fr/bourses", "/fr/connexion"] do
    test "every inline script of #{path} is allowed by its hash" do
      mode(:report_only)
      conn = get(build_conn(), unquote(path))
      html = html_response(conn, 200)
      [policy] = get_resp_header(conn, "content-security-policy-report-only")

      scripts = inline_scripts(html)
      assert scripts != []

      for script <- scripts do
        assert policy =~ sha256(script),
               "inline script not in the policy (edit lib/syli_atlas_web/csp/, not the layout):\n" <>
                 String.slice(script, 0, 200)
      end
    end
  end

  test "the 404 page carries the policy and its scripts are allowed" do
    mode(:report_only)

    {404, headers, html} =
      assert_error_sent(404, fn -> get(build_conn(), "/fr/pays/atlantide") end)

    {_, policy} = List.keyfind(headers, "content-security-policy-report-only", 0)
    for script <- inline_scripts(html), do: assert(policy =~ sha256(script))
  end

  test "report-only keeps Phoenix's enforced policy and adds the full one" do
    mode(:report_only)
    conn = get(build_conn(), "/en")

    assert get_resp_header(conn, "content-security-policy") == [
             "base-uri 'self'; frame-ancestors 'self';"
           ]

    assert [policy] = get_resp_header(conn, "content-security-policy-report-only")
    assert policy == CSP.policy()
    assert policy =~ "default-src 'self'"
    assert policy =~ "object-src 'none'"
    assert policy =~ "report-uri /csp-report"
    refute policy =~ "unsafe-eval"
    refute policy =~ ~r/script-src[^;]*unsafe-inline/
    assert [endpoints] = get_resp_header(conn, "reporting-endpoints")
    assert endpoints =~ ~r{^csp="https?://[^"]+/csp-report"$}
  end

  test "enforce sends the full policy as Content-Security-Policy" do
    mode(:enforce)
    conn = get(build_conn(), "/en")
    assert get_resp_header(conn, "content-security-policy") == [CSP.policy()]
    assert get_resp_header(conn, "content-security-policy-report-only") == []
  end

  test "off leaves only Phoenix's policy" do
    mode(:off)
    conn = get(build_conn(), "/en")

    assert get_resp_header(conn, "content-security-policy") == [
             "base-uri 'self'; frame-ancestors 'self';"
           ]

    assert get_resp_header(conn, "content-security-policy-report-only") == []
  end

  test "JSON answers carry no policy" do
    mode(:enforce)
    conn = get(build_conn(), "/api/v1/areas")
    assert get_resp_header(conn, "content-security-policy-report-only") == []
    assert get_resp_header(conn, "reporting-endpoints") == []
  end

  describe "POST /csp-report" do
    test "logs a report-uri report" do
      body =
        Jason.encode!(%{
          "csp-report" => %{
            "document-uri" => "https://syliatlas.com/en",
            "effective-directive" => "script-src-elem",
            "blocked-uri" => "inline",
            "source-file" => "https://syliatlas.com/en",
            "line-number" => 12
          }
        })

      log =
        capture_log(fn ->
          conn =
            build_conn()
            |> put_req_header("content-type", "application/csp-report")
            |> post("/csp-report", body)

          assert response(conn, 204) == ""
        end)

      assert log =~ "csp violation"
      assert log =~ ~s(directive="script-src-elem")
      assert log =~ ~s(blocked="inline")
      assert log =~ ~s(source="https://syliatlas.com/en:12")
    end

    test "logs Reporting API reports and ignores other types" do
      body =
        Jason.encode!([
          %{
            "type" => "csp-violation",
            "body" => %{
              "documentURL" => "https://syliatlas.com/fr/bourses",
              "effectiveDirective" => "connect-src",
              "blockedURL" => "https://evil.example/x"
            }
          },
          %{"type" => "deprecation", "body" => %{"id" => "x"}}
        ])

      log =
        capture_log(fn ->
          conn =
            build_conn()
            |> put_req_header("content-type", "application/reports+json")
            |> post("/csp-report", body)

          assert response(conn, 204) == ""
        end)

      assert log =~ ~s(directive="connect-src")
      assert log =~ ~s(blocked="https://evil.example/x")
      refute log =~ "deprecation"
    end

    test "answers 204 to anything else, without logging" do
      log =
        capture_log(fn ->
          conn =
            build_conn()
            |> put_req_header("content-type", "text/plain")
            |> post("/csp-report", "not json")

          assert response(conn, 204) == ""
        end)

      refute log =~ "csp violation"
    end
  end
end
