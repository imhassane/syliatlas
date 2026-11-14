// « Copy » buttons: <button type="button" data-copy="#field" hidden>, with a
// sibling <span role="status" data-copy-status> (outside the button: a live
// region inside a button is not reliably announced). Hidden without
// JavaScript (the field stays selectable); shown here, they copy the field's
// text and say so, success or failure, on the button and to screen readers.
const timers = new WeakMap()

export function initCopyButtons() {
  document.querySelectorAll("[data-copy]").forEach(button => {
    const field = document.querySelector(button.dataset.copy)
    if (!field || !navigator.clipboard) return
    const label = button.textContent.trim()
    const status = button.parentElement?.querySelector("[data-copy-status]")
    button.hidden = false

    const report = (message) => {
      clearTimeout(timers.get(button))
      button.textContent = message
      if (status) {
        status.textContent = ""
        requestAnimationFrame(() => { status.textContent = message })
      }
      // Never disabled meanwhile: copying again is harmless, and focus stays.
      timers.set(button, setTimeout(() => {
        button.textContent = label
        if (status) status.textContent = ""
      }, 2000))
    }

    button.addEventListener("click", async () => {
      const text = field.matches("input, textarea") ? field.value : field.innerText.trim()
      try {
        await navigator.clipboard.writeText(text)
        report(button.dataset.copied || "✓")
      } catch (e) {
        report(button.dataset.copyFailed || "×")
        field.select?.()
      }
    })
  })
}
