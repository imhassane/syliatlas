// New versions: the page knows what it was built from (<meta name="syli-version">:
// code and data). The service worker installs each deploy, and /api/internal/version
// is checked when the tab comes back and every 15 minutes. When something
// changed, a toast offers to refresh; refreshing never needs Ctrl+R.
//
// The toast is offered once per version and session: once the reader chose
// « refresh » or « later » for a version, it does not come back for it (a
// refresh that still lands on the old version during a deploy, other pages,
// other tabs). A new service worker for the build the page already shows
// takes over silently: the page is up to date, only the worker was behind.
import {toast, strings} from "./toasts"

const t = strings
const SEEN = "update-seen"
let waitingWorker = null
let offered = false

const seen = target => { try { return sessionStorage.getItem(SEEN) === target } catch (_) { return false } }
const remember = target => { try { sessionStorage.setItem(SEEN, target) } catch (_) {} }

export async function refresh() {
  if (waitingWorker) {
    // The new worker takes over, then the page reloads once (controllerchange).
    waitingWorker.postMessage("skip-waiting")
    return
  }
  try { await fetch(location.href, {cache: "reload", credentials: "same-origin"}) } catch (_) {}
  location.reload()
}

function offer(kind, target) {
  if (offered || !target || seen(target)) return
  offered = true
  toast({
    id: "update",
    icon: "update",
    message: kind === "data" ? t().data_message : t().update_message,
    description: kind === "data" ? t().data_description : t().update_description,
    action: {label: t().refresh, onClick: () => { remember(target); refresh() }},
    cancel: {label: t().later, onClick: () => { remember(target); offered = false }},
  })
}

async function checkVersion() {
  const current = document.querySelector('meta[name="syli-version"]')?.content
  if (!current || !navigator.onLine) return
  try {
    const res = await fetch("/api/internal/version", {cache: "no-store"})
    if (!res.ok) return
    const {page_version: latest, build} = await res.json()
    if (latest && latest !== current) offer(current.split(".")[0] === build ? "data" : "code", latest)
  } catch (_) {}
}

export function initUpdates() {
  const build = document.querySelector('meta[name="syli-build"]')?.content

  const secure = location.protocol === "https:" || location.hostname === "localhost"
  if ("serviceWorker" in navigator && build && secure) {
    navigator.serviceWorker.register(`/sw.js?v=${encodeURIComponent(build)}`).then(reg => {
      const waiting = worker => {
        const v = new URL(worker.scriptURL).searchParams.get("v")
        // Installed for the build this page already shows: take over, no toast, no reload.
        if (v === build) return worker.postMessage("skip-waiting")
        waitingWorker = worker
        offer("code", "build:" + v)
      }
      const track = worker => {
        worker?.addEventListener("statechange", () => {
          if (worker.state === "installed" && navigator.serviceWorker.controller) waiting(worker)
        })
      }
      if (reg.waiting && navigator.serviceWorker.controller) waiting(reg.waiting)
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
