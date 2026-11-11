defmodule SyliAtlasWeb.CSP do
  @moduledoc """
  The Content-Security-Policy of HTML pages.

  Scripts run only from the site itself (`/assets/js/*.js`, `/sw.js`,
  Cloudflare's `/cdn-cgi/` e-mail decoder) and the few inline scripts of the
  root layout, allowed by their SHA-256 hash. Those inline scripts live in
  `lib/syli_atlas_web/csp/` and are rendered, tag included, by `script/1`, so
  the hash is computed from the very bytes the page carries (the browser
  hashes them whitespace included): edit the file, never the layout. No nonce: the hash does not change from one response to the next,
  so pages stay cacheable (ETag, service worker).

  `<script type="application/json">` and `application/ld+json` blocks are
  data, never run, and need nothing here.

  Styles: stylesheets from the site; `style="…"` attributes stay allowed
  (`style-src-attr`), they cannot run code.

  The mode comes from `CSP_MODE` (config/runtime.exs):

    * `:report_only` (default) — Phoenix's enforced policy (base-uri,
      frame-ancestors) stays; the full policy is sent as
      `Content-Security-Policy-Report-Only`, violations go to `/csp-report`
      and the logs (SyliAtlasWeb.CspReportController).
    * `:enforce` — the full policy is `Content-Security-Policy`.
    * `:off` — only Phoenix's policy.
  """

  import Plug.Conn

  @dir Path.join(__DIR__, "csp")
  @files [boot: "boot.js", arrival: "arrival.js", speculation_rules: "speculation_rules.json"]

  for {_key, file} <- @files, do: @external_resource(Path.join(@dir, file))

  @sources Map.new(@files, fn {key, file} ->
             {key, @dir |> Path.join(file) |> File.read!() |> String.trim()}
           end)

  @hashes @sources
          |> Map.values()
          |> Enum.map(&"'sha256-#{Base.encode64(:crypto.hash(:sha256, &1))}'")
          |> Enum.sort()

  @report_path "/csp-report"

  @types [speculation_rules: ~s( type="speculationrules")]

  @doc """
  An inline script of the root layout, `<script>` tag included: written in
  the template, its body would be re-indented by the formatter and no longer
  match its hash.
  """
  def script(key) do
    Phoenix.HTML.raw("<script#{@types[key]}>" <> Map.fetch!(@sources, key) <> "</script>")
  end

  @doc "The `'sha256-…'` sources of the inline scripts."
  def hashes, do: @hashes

  @doc "Where browsers send violation reports."
  def report_path, do: @report_path

  def mode, do: Application.get_env(:syli_atlas, __MODULE__, [])[:mode] || :report_only

  @doc "The full policy."
  def policy do
    url = SyliAtlasWeb.Endpoint.struct_url()

    Enum.join(
      [
        "default-src 'self'",
        Enum.join(["script-src 'self'" | @hashes], " "),
        "style-src 'self'",
        "style-src-attr 'unsafe-inline'",
        "img-src 'self' data:",
        "font-src 'self'",
        # The LiveView socket. 'self' covers it in current browsers; older
        # Safari wants the ws(s) origin written out.
        "connect-src 'self' #{socket_origin(url)}",
        "worker-src 'self'",
        "manifest-src 'self'",
        "frame-src 'self'",
        "object-src 'none'",
        "base-uri 'self'",
        "frame-ancestors 'self'",
        "form-action 'self'",
        "report-uri #{@report_path}",
        "report-to csp"
      ],
      "; "
    )
  end

  @doc """
  Plug: adds the policy to HTML responses, just before they are sent, so it
  covers every page (error pages included) whatever pipeline drew it.
  """
  def init(opts), do: opts

  def call(conn, _opts) do
    case mode() do
      :off -> conn
      mode -> register_before_send(conn, &put_policy(&1, mode))
    end
  end

  defp put_policy(conn, mode) do
    if html?(conn) do
      header =
        if mode == :enforce,
          do: "content-security-policy",
          else: "content-security-policy-report-only"

      conn
      |> put_resp_header(header, policy())
      |> put_resp_header("reporting-endpoints", ~s(csp="#{report_url()}"))
    else
      conn
    end
  end

  defp html?(conn) do
    Enum.any?(get_resp_header(conn, "content-type"), &String.starts_with?(&1, "text/html"))
  end

  defp report_url do
    SyliAtlasWeb.Endpoint.struct_url() |> Map.put(:path, @report_path) |> URI.to_string()
  end

  defp socket_origin(%URI{scheme: scheme} = url) do
    ws = if scheme == "https", do: "wss", else: "ws"
    %URI{url | scheme: ws, path: nil} |> URI.to_string()
  end
end
