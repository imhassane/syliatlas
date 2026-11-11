// New versions: the page knows what it was built from (<meta name="syli-version">:
// code and data). The service worker installs each deploy, and /api/v1/version
// is checked when the tab comes back and every 15 minutes. When something
// changed, a toast offers to refresh; refreshing never needs Ctrl+R.
import {toast, strings} from "./toasts"

const t = strings
let waitingWorker = null
let offered = false

export async function refresh() {
  if (waitingWorker) {
    // The new worker takes over, then the page reloads once (controllerchange).
    waitingWorker.postMessage("skip-waiting")
    return
  }
  try { await fetch(location.href, {cache: "reload", credentials: "same-origin"}) } catch (_) {}
  location.reload()
}

function offer(kind) {
  if (offered) return
  offered = true
  toast({
    id: "update",
    icon: "update",
    message: kind === "data" ? t().data_message : t().update_message,
    description: kind === "data" ? t().data_description : t().update_description,
    action: {label: t().refresh, onClick: refresh},
    cancel: {label: t().later, onClick: () => { offered = false }},
  })
}

async function checkVersion() {
  const current = document.querySelector('meta[name="syli-version"]')?.content
  if (!current || !navigator.onLine) return
  try {
    const res = await fetch("/api/v1/version", {cache: "no-store"})
    if (!res.ok) return
    const {page_version: latest, build} = await res.json()
    if (latest && latest !== current) offer(current.split(".")[0] === build ? "data" : "code")
  } catch (_) {}
}

export function initUpdates() {
  const build = document.querySelector('meta[name="syli-build"]')?.content

  const secure = location.protocol === "https:" || location.hostname === "localhost"
  if ("serviceWorker" in navigator && build && secure) {
    navigator.serviceWorker.register(`/sw.js?v=${encodeURIComponent(build)}`).then(reg => {
      const track = worker => {
        worker?.addEventListener("statechange", () => {
          if (worker.state === "installed" && navigator.serviceWorker.controller) { waitingWorker = worker; offer("code") }
        })
      }
      if (reg.waiting && navigator.serviceWorker.controller) { waitingWorker = reg.waiting; offer("code") }
      reg.addEventListener("updatefound", () => track(reg.installing))
    }).catch(() => {})

    let reloaded = false
    navigator.serviceWorker.addEventListener("controllerchange", () => {
      if (!waitingWorker || reloaded) return
      reloaded = true
      location.reload()
    })
  }

  document.addEventListener("visibilitychange", () => { if (!document.hidden) checkVersion() })
  setInterval(checkVersion, 15 * 60 * 1000)
  setTimeout(checkVersion, 4000)

  // Online / offline: the banner and a short toast.
  const setOffline = off => document.documentElement.classList.toggle("is-offline", off)
  addEventListener("offline", () => { setOffline(true); toast({id: "network", kind: "warning", message: t().offline_message, description: t().offline_description}) })
  addEventListener("online", () => { setOffline(false); toast({id: "network", kind: "success", message: t().online_message, duration: 4000}); checkVersion() })
}
