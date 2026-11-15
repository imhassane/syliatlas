// A link to a folded panel (#rebasage) opens it: on load, and when the
// address's fragment changes on the same page. Without JavaScript the panel
// stays folded and its content is still in the page.
export function initDetailsTarget() {
  const open = () => {
    const id = decodeURIComponent(location.hash.slice(1))
    if (!id) return
    const el = document.getElementById(id)
    if (el instanceof HTMLDetailsElement && !el.open) el.open = true
  }
  open()
  window.addEventListener("hashchange", open)
  window.addEventListener("pageshow", open)
}
