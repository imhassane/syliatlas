// Syli Atlas service worker.
//
// Registered as /sw.js?v=<build>: a deploy changes the URL, so the browser
// installs the new worker; the page then offers to refresh (a toast) and
// asks it to take over ("skip-waiting").
//
//   pages: network first (revalidated, a cheap 304), the cached copy when
//          offline — the last version of every page read stays readable;
//   /assets, /images, fonts: cache first (asset names change with content);
//   /api: network first, cached copy offline.
const VERSION = new URL(self.location).searchParams.get("v") || "dev"
const PAGES = "pages-" + VERSION
const STATIC = "static-" + VERSION
const API = "api-v1"
const OFFLINE_START = ["/fr", "/en"]

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

self.addEventListener("message", event => {
  if (event.data === "skip-waiting") self.skipWaiting()
})

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
      const lang = new URL(request.url).pathname.startsWith("/en") ? "/en" : "/fr"
      const home = await cache.match(lang)
      if (home) return home
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
    if (url.pathname.startsWith("/api/v1/version")) return
    if (url.pathname.startsWith("/api/")) return event.respondWith(networkFirst(request, API))
    if (/^\/(assets|images|fonts)\//.test(url.pathname)) return event.respondWith(cacheFirst(request))
  }
  // Other origins (web fonts): left to the browser and its HTTP cache.
})
