// Toasts in the Sonner manner, in the Sily theme (as in the Kalanso
// workshop): white cards with a hairline, bottom of the end edge, the newest
// in front and the others folded behind; pointed at or focused, the stack
// unfolds. Information closes by itself after `duration`, paused while
// pointed at, focused or the tab is hidden; a toast with an action stays.
//
//   toast({id, kind: "info"|"success"|"warning"|"error", message, description,
//          action: {label, onClick}, cancel: {label, onClick}, duration})
//
// A toast with the same id replaces the previous one.

const ICONS = {
  info: '<circle cx="12" cy="12" r="9"></circle><path d="M12 11v5M12 8h.01"></path>',
  success: '<circle cx="12" cy="12" r="9"></circle><path d="M8 12.5l2.5 2.5L16 9.5"></path>',
  warning: '<path d="M12 3l9.5 17h-19z"></path><path d="M12 10v4M12 17h.01"></path>',
  error: '<circle cx="12" cy="12" r="9"></circle><path d="M12 7.5v5.5M12 16.5h.01"></path>',
  update: '<path d="M20 12a8 8 0 1 1-2.3-5.6"></path><path d="M20 4v5h-5"></path>',
  install: '<rect x="6" y="2.5" width="12" height="19" rx="2.5"></rect><path d="M12 7v7M9 11l3 3 3-3"></path>',
}

let area = null
export const strings = () => (window.syliStrings ||= JSON.parse(document.getElementById("ui-strings")?.textContent || "{}"))

function region() {
  if (area) return area
  area = document.getElementById("toasts")
  let hovered = false
  area.addEventListener("pointerenter", () => { hovered = true; pauseAll() })
  area.addEventListener("pointerleave", () => { hovered = false; resumeAll() })
  area.addEventListener("focusin", pauseAll)
  area.addEventListener("focusout", () => { if (!hovered) resumeAll() })
  document.addEventListener("visibilitychange", () => (document.hidden ? pauseAll() : resumeAll()))
  return area
}

const timers = new Map()
function pauseAll() { timers.forEach(t => { clearTimeout(t.handle); t.left -= Date.now() - t.start }) }
function resumeAll() { timers.forEach((t, el) => { t.start = Date.now(); t.handle = setTimeout(() => dismiss(el), Math.max(t.left, 1500)) }) }

export function dismiss(el) {
  if (!el || !el.isConnected) return
  clearTimeout(timers.get(el)?.handle)
  timers.delete(el)
  el.classList.add("is-leaving")
  setTimeout(() => el.remove(), 200)
}

export function toast({id, kind = "info", icon, message, description, action, cancel, duration = 6000}) {
  const root = region()
  if (id) root.querySelector(`[data-toast-id="${id}"]`)?.remove()

  const el = document.createElement("div")
  el.className = "toast"
  el.dataset.kind = kind
  if (id) el.dataset.toastId = id
  el.setAttribute("role", kind === "error" ? "alert" : "status")
  el.innerHTML = `
    <span class="toast-icon" aria-hidden="true"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${ICONS[icon || kind] || ICONS.info}</svg></span>
    <div class="toast-text"><p class="toast-message"></p>${description ? '<p class="toast-description"></p>' : ""}</div>
    <div class="toast-actions"></div>
    <button type="button" class="toast-close"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"></path></svg><span class="vh"></span></button>`
  el.querySelector(".toast-message").textContent = message
  if (description) el.querySelector(".toast-description").textContent = description
  el.querySelector(".toast-close .vh").textContent = strings().close || "Close"
  el.querySelector(".toast-close").addEventListener("click", () => { cancel?.onClick?.(); dismiss(el) })

  const actions = el.querySelector(".toast-actions")
  for (const [def, cls] of [[cancel, "btn btn-quiet btn-sm"], [action, "btn btn-primary btn-sm"]]) {
    if (!def) continue
    const b = document.createElement("button")
    b.type = "button"; b.className = cls; b.textContent = def.label
    b.addEventListener("click", () => { def.onClick?.(); if (def.keep !== true) dismiss(el) })
    actions.append(b)
  }
  if (!actions.children.length) actions.remove()

  root.append(el)
  if (!action && duration) {
    const t = {start: Date.now(), left: duration}
    t.handle = setTimeout(() => dismiss(el), duration)
    timers.set(el, t)
  }
  return el
}

// The server's flash messages (put_flash in the controllers), handed over by
// the root layout as JSON in #flash-toasts: each becomes a toast. Errors stay
// on screen longer than information.
export function showFlash(flashes) {
  for (const {kind, message} of flashes || []) {
    if (!message) continue
    toast({id: `flash-${kind}`, kind: kind === "error" ? "error" : "success", message, duration: kind === "error" ? 10000 : 6000})
  }
}

export function initFlashToasts() {
  const data = document.getElementById("flash-toasts")
  if (!data) return
  showFlash(JSON.parse(data.textContent || "[]"))
  data.remove()
}
