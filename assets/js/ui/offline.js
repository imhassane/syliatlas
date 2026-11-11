// Offline reading: after a page has loaded, ask the service worker to save
// the country, region and main pages of this language (see sw.js). Once per
// build and language, only on a connection that allows it (no data saver,
// not 2G), and when the browser is idle.
const KEY = "pages-saved"

function connectionAllows() {
  const c = navigator.connection
  if (!c) return true
  return !c.saveData && !/(^|-)2g$/.test(c.effectiveType || "")
}

// The files this page loaded (stylesheet, script, fonts, icons): on a first
// visit they load before the service worker controls the page, so it is
// told about them at once, or saved pages would show unstyled offline.
function loadedAssets() {
  return performance.getEntriesByType("resource").map(e => e.name).filter(u => {
    const url = new URL(u)
    return url.origin === location.origin && /^\/(assets|images|fonts)\//.test(url.pathname)
  })
}

export function initOfflinePages() {
  if (!("serviceWorker" in navigator)) return
  // The offline page shows when the device was last online.
  if (navigator.onLine) try { localStorage.setItem("last-online", String(Date.now())) } catch (_) {}
  addEventListener("load", () => {
    navigator.serviceWorker.ready.then(reg => reg.active?.postMessage({type: "save-assets", assets: loadedAssets()}))
  }, {once: true})

  if (!navigator.onLine || !connectionAllows()) return
  const build = document.querySelector('meta[name="syli-build"]')?.content
  const locale = location.pathname.split("/")[1] || "fr"
  const mark = `${build}:${locale}`
  try { if (localStorage.getItem(KEY) === mark) return } catch (_) {}

  navigator.serviceWorker.addEventListener("message", event => {
    const {type, locale: done, saved, total} = event.data || {}
    if (type === "pages-saved" && done === locale && saved === total) {
      try { localStorage.setItem(KEY, mark) } catch (_) {}
    }
  })

  const ask = () => navigator.serviceWorker.ready.then(reg => reg.active?.postMessage({type: "save-pages", locale}))
  const idle = window.requestIdleCallback || (fn => setTimeout(fn, 3000))
  addEventListener("load", () => setTimeout(() => idle(ask, {timeout: 10000}), 2000), {once: true})
}
