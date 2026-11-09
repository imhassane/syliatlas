// Light and dark themes. The first paint is set by an inline script in the
// root layout (no flash); this keeps it in sync with the toggle and the OS.
export function initTheme() {
  const root = document.documentElement
  const set = theme => {
    root.dataset.theme = theme
    document.querySelector('meta[name="theme-color"]')?.setAttribute("content", theme === "dark" ? "#0a1220" : "#ffffff")
  }

  document.addEventListener("click", event => {
    if (!event.target.closest("[data-theme-toggle]")) return
    const next = root.dataset.theme === "dark" ? "light" : "dark"
    set(next)
    try { localStorage.setItem("theme", next) } catch (_) {}
  })

  matchMedia("(prefers-color-scheme: dark)").addEventListener("change", e => {
    let saved = null
    try { saved = localStorage.getItem("theme") } catch (_) {}
    if (!saved) set(e.matches ? "dark" : "light")
  })

  set(root.dataset.theme || "light")
}
