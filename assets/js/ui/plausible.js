// Visit counts with Plausible: no cookie, nothing stored in the browser, no
// personal data, so no consent banner.
//
// The snippet Plausible gives (a queue stub, then its script) is written
// here rather than inline in the layout, so a strict Content-Security-Policy
// only has to allow https://plausible.io (script-src and connect-src).
//
//   * production only (syliatlas.com): dev.syliatlas.com and local runs are
//     never counted;
//   * a page prerendered on hover (speculation rules) and never opened is not
//     counted: the script loads once the page is really shown;
//   * admin pages and framed views (/embed) are not counted.

const SCRIPT = "https://plausible.io/js/pa-tqJfmtlViEzrVhjP3zoA3.js"
const HOSTS = ["syliatlas.com", "www.syliatlas.com"]

function load() {
  if (document.querySelector(`script[src="${SCRIPT}"]`)) return

  // Plausible's own stub: calls made before its script arrives are queued.
  window.plausible = window.plausible || function () {
    (window.plausible.q = window.plausible.q || []).push(arguments)
  }
  window.plausible.init = window.plausible.init || function (options) {
    window.plausible.o = options || {}
  }
  window.plausible.init()

  const script = document.createElement("script")
  script.async = true
  script.src = SCRIPT
  document.head.appendChild(script)
}

export function initPlausible() {
  if (!HOSTS.includes(location.hostname)) return
  if (/^\/(admin|dev|embed)(\/|$)/.test(location.pathname)) return

  if (document.prerendering) {
    document.addEventListener("prerenderingchange", load, {once: true})
  } else {
    load()
  }
}
