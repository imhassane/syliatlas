// Syli Atlas service worker.
//
// Registered as /sw.js?v=<build>: a deploy changes the URL, so the browser
// installs the new worker; the page then offers to refresh (a toast) and
// asks it to take over ("skip-waiting").
//
//   pages: network first (revalidated, a cheap 304), the cached copy when
//          offline — the last version of every page read stays readable;
//          a page never saved shows the offline page (/fr/hors-ligne);
//   /assets, /images, fonts: cache first (asset names change with content);
//   /api: network first, cached copy offline.
//
// Offline reading: each page lists the files it loaded ({type: "save-assets"}),
// and once a page asks ({type: "save-pages", locale}), the
// worker saves every country, region and main page of that language that
// it does not hold yet (list from /api/internal/offline-pages), one at a time,
// and stops at the first network failure.
const VERSION = new URL(self.location).searchParams.get("v") || "dev"
const PAGES = "pages-" + VERSION
const STATIC = "static-" + VERSION
const API = "api-v1"
// The offline page of each language of the site (SyliAtlasWeb.Paths.offline/1).
const OFFLINE_PAGES = {fr: "/fr/hors-ligne", en: "/en/offline", es: "/es/sin-conexion", pt: "/pt/offline", ar: "/ar/offline", hi: "/hi/offline", zh: "/zh/offline"}
const OFFLINE_START = ["/fr", "/en", "/fr/hors-ligne", "/en/offline"]

self.addEventListener("install", event => {
  event.waitUntil(caches.open(PAGES).then(cache => cache.addAll(OFFLINE_START)).catch(() => {}))
})

self.addEventListener("activate", event => {
  event.waitUntil((async () => {
    const keep = [PAGES, STATIC, API]
    for (const key of await caches.keys()) if (!keep.includes(key)) await caches.delete(key)
    await self.clients.claim()
  })())
})

let saving = null

self.addEventListener("message", event => {
  if (event.data === "skip-waiting") self.skipWaiting()
  if (event.data?.type === "save-assets") event.waitUntil(saveAssets(event.data.assets))
  if (event.data?.type === "save-pages" && !saving) {
    const locale = event.data.locale in OFFLINE_PAGES ? event.data.locale : "fr"
    saving = savePages(locale).finally(() => { saving = null })
    event.waitUntil(saving)
  }
})

// The stylesheet, script and fonts of the first visit load before this
// worker controls the page, so the page lists them and they are saved here:
// without them, saved pages would show unstyled offline.
async function saveAssets(urls) {
  const cache = await caches.open(STATIC)
  for (const url of urls || []) {
    const {origin, pathname} = new URL(url, location.origin)
    if (origin !== location.origin || !/^\/(assets|images|fonts)\//.test(pathname)) continue
    if (await cache.match(url)) continue
    try { const res = await fetch(url); if (res.ok) await cache.put(url, res) } catch (_) { return }
  }
}

async function savePages(locale) {
  const cache = await caches.open(PAGES)
  let paths
  try {
    const res = await fetch(`/api/internal/offline-pages?locale=${locale}`)
    if (!res.ok) return
    paths = (await res.json()).pages
  } catch (_) { return }
  let saved = 0
  for (const path of paths) {
    if (await cache.match(path)) { saved++; continue }
    try {
      const res = await fetch(path, {credentials: "same-origin"})
      if (res.ok) { await cache.put(path, res); saved++ }
    } catch (_) { break }
    // Leave room for what the visitor is doing.
    await new Promise(resolve => setTimeout(resolve, 150))
  }
  for (const client of await self.clients.matchAll()) client.postMessage({type: "pages-saved", locale, saved, total: paths.length})
}

async function networkFirst(request, cacheName) {
  const cache = await caches.open(cacheName)
  try {
    const response = await fetch(request, {cache: "no-cache"})
    if (response.ok) cache.put(request, response.clone())
    return response
  } catch (error) {
    const cached = await cache.match(request, {ignoreVary: true})
    if (cached) return cached
    if (request.mode === "navigate") {
      // Not saved: the offline page, shown under the asked address (it says
      // which page and lists the saved ones), else the home page.
      const first = new URL(request.url).pathname.split("/")[1]
      const lang = first in OFFLINE_PAGES ? first : "fr"
      const fallback = (await cache.match(OFFLINE_PAGES[lang])) || (await cache.match("/" + lang))
      if (fallback) return fallback
    }
    throw error
  }
}

async function cacheFirst(request) {
  const cache = await caches.open(STATIC)
  const cached = await cache.match(request)
  if (cached) return cached
  const response = await fetch(request)
  if (response.ok) cache.put(request, response.clone())
  return response
}

self.addEventListener("fetch", event => {
  const {request} = event
  if (request.method !== "GET") return
  const url = new URL(request.url)

  if (url.origin === location.origin) {
    if (url.pathname.startsWith("/live") || url.pathname.startsWith("/phoenix") || url.pathname.startsWith("/admin")) return
    if (request.mode === "navigate") return event.respondWith(networkFirst(request, PAGES))
    if (url.pathname.startsWith("/api/internal/version") || url.pathname.startsWith("/api/v1/version")) return
    if (url.pathname.startsWith("/api/")) return event.respondWith(networkFirst(request, API))
    if (/^\/(assets|images|fonts)\//.test(url.pathname)) return event.respondWith(cacheFirst(request))
  }
  // Other origins (web fonts): left to the browser and its HTTP cache.
})
