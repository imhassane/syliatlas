// Visit counts: Cloudflare Web Analytics, without cookies (SyliAtlasWeb.WebAnalytics).
// The layout writes <meta name="cf-web-analytics"> only when the token is set.
// The beacon loads once the page is really shown: a page prerendered on hover
// (speculation rules) and never opened is not counted. Admin pages are not counted.
const BEACON = "https://static.cloudflareinsights.com/beacon.min.js"

function load(token) {
  const script = document.createElement("script")
  script.defer = true
  script.src = BEACON
  script.dataset.cfBeacon = JSON.stringify({token})
  document.head.appendChild(script)
}

export function initAnalytics() {
  const token = document.querySelector('meta[name="cf-web-analytics"]')?.content
  if (!token || /^\/(admin|dev)(\/|$)/.test(location.pathname)) return

  if (document.prerendering) {
    document.addEventListener("prerenderingchange", () => load(token), {once: true})
  } else {
    load(token)
  }
}
