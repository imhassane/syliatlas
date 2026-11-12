defmodule SyliAtlasWeb.WebAnalytics do
  @moduledoc """
  Visit counts with Cloudflare Web Analytics: no cookie, nothing stored in
  the browser, no personal data, so no consent banner.

  Set by hand, never by Cloudflare's automatic injection (turn it off in the
  dashboard: Analytics & Logs > Web Analytics > the site > Manage site >
  automatic setup off). Injected, the beacon would also land in the framed
  views (`/embed/…`), which promise no tracking, and Cloudflare's script
  would have to be allowed in their policy.

  How it works:

    * the root layout writes `<meta name="cf-web-analytics" content=TOKEN>`
      when `CLOUDFLARE_WEB_ANALYTICS_TOKEN` is set (config/runtime.exs);
      the framed views have no root layout, so never get it;
    * `assets/js/ui/analytics.js` then loads Cloudflare's beacon, but only
      once the page is really shown: a page prerendered on hover (speculation
      rules) and never opened is not counted; nor are admin pages;
    * `SyliAtlasWeb.CSP` allows the beacon's script and endpoint in the
      site's policy, only when the token is set; never in the embed policy.

  Without the variable nothing is loaded and the policy is unchanged.
  """

  @script_origin "https://static.cloudflareinsights.com"
  @connect_origin "https://cloudflareinsights.com"

  @doc "The site token of Cloudflare Web Analytics, or nil."
  def token do
    case Application.get_env(:syli_atlas, __MODULE__, [])[:token] do
      token when is_binary(token) and token != "" -> token
      _ -> nil
    end
  end

  def enabled?, do: token() != nil

  @doc "Where the beacon script comes from (CSP `script-src`)."
  def script_origin, do: @script_origin

  @doc "Where the beacon sends its measures (CSP `connect-src`)."
  def connect_origin, do: @connect_origin
end
