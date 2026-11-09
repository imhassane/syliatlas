// Installing the app (PWA). Chrome, Edge and Android fire beforeinstallprompt:
// the [data-install] buttons appear (header, menu, home card) and, from the
// second visit, a toast suggests it once a month. iPhone and iPad have no
// prompt: the toast explains Share → Add to Home Screen instead.
import {toast, strings} from "./toasts"

const t = strings
const MONTH = 30 * 24 * 3600 * 1000
let deferred = null

const standalone = () => matchMedia("(display-mode: standalone)").matches || navigator.standalone === true
const ios = () => /iphone|ipad|ipod/i.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)

function store(key, value) { try { value === undefined ? localStorage.removeItem(key) : localStorage.setItem(key, value) } catch (_) {} }
function read(key) { try { return localStorage.getItem(key) } catch (_) { return null } }

export async function install() {
  if (!deferred) return
  deferred.prompt()
  const {outcome} = await deferred.userChoice
  deferred = null
  document.documentElement.classList.remove("can-install")
  if (outcome === "accepted") toast({kind: "success", message: t().installed_message, duration: 4000})
}

function nudgeAllowed() {
  const visits = Number(read("visits") || 0) + 1
  store("visits", String(visits))
  const last = Number(read("install-nudge") || 0)
  return visits >= 2 && Date.now() - last > MONTH
}

function nudge(onIos) {
  setTimeout(() => {
    if (standalone()) return
    store("install-nudge", String(Date.now()))
    toast({
      id: "install",
      icon: "install",
      message: t().install_message,
      description: onIos ? t().install_ios : t().install_description,
      action: onIos ? undefined : {label: t().install, onClick: install},
      cancel: {label: t().not_now},
      duration: onIos ? 12000 : 0,
    })
  }, 20000)
}

export function initInstall() {
  if (standalone()) return
  const allowed = nudgeAllowed()

  addEventListener("beforeinstallprompt", event => {
    event.preventDefault()
    deferred = event
    document.documentElement.classList.add("can-install")
    if (allowed) nudge(false)
  })
  addEventListener("appinstalled", () => document.documentElement.classList.remove("can-install"))

  document.addEventListener("click", event => {
    if (event.target.closest("[data-install], [data-install-button]")?.matches("button")) install()
  })

  if (ios() && allowed) nudge(true)
}
