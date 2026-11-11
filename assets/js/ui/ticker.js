// The band under the header: its pause button. Without this script the band
// still pauses on hover and on focus; the button only shows with it. The
// choice is kept on the device, so the band stays still from page to page.
const KEY = "ticker-paused"

export function initTicker() {
  const band = document.querySelector("[data-ticker]")
  const button = band?.querySelector("[data-ticker-pause]")
  if (!button) return

  const set = paused => {
    band.classList.toggle("is-paused", paused)
    button.setAttribute("aria-pressed", paused ? "true" : "false")
    const label = paused ? button.dataset.labelPlay : button.dataset.labelPause
    button.setAttribute("aria-label", label)
    button.title = label
  }

  let saved = false
  try { saved = localStorage.getItem(KEY) === "1" } catch (_) {}
  set(saved)
  button.hidden = false

  button.addEventListener("click", () => {
    const paused = !band.classList.contains("is-paused")
    set(paused)
    try { paused ? localStorage.setItem(KEY, "1") : localStorage.removeItem(KEY) } catch (_) {}
  })
}
