// Modal windows opened by a link: <a href="?ajouter=1" data-dialog-open="id">.
// Without JavaScript the link loads the page with the window already open
// (the server renders the <dialog open>); with it, the window opens in place.
// Escape, the close button and a click on the backdrop close it.
export function initDialogs() {
  document.addEventListener("click", (event) => {
    const opener = event.target.closest("[data-dialog-open]")
    if (opener) {
      const dialog = document.getElementById(opener.dataset.dialogOpen)
      if (dialog && typeof dialog.showModal === "function") {
        event.preventDefault()
        if (!dialog.open) dialog.showModal()
        dialog.querySelector("[autofocus], input, select")?.focus()
      }
      return
    }

    const closer = event.target.closest("[data-dialog-close]")
    if (closer) {
      const dialog = closer.closest("dialog")
      if (dialog) {
        event.preventDefault()
        close(dialog)
      }
      return
    }

    // A click on the backdrop: the target is the dialog itself.
    if (event.target instanceof HTMLDialogElement && event.target.matches("[data-dialog]")) {
      const r = event.target.getBoundingClientRect()
      const inside = event.clientX >= r.left && event.clientX <= r.right && event.clientY >= r.top && event.clientY <= r.bottom
      if (!inside) close(event.target)
    }
  })

  // However it closes (button, backdrop, Escape): drop ?ajouter=1 from the
  // address, so a reload does not open it again.
  document.querySelectorAll("dialog[data-dialog]").forEach((dialog) => {
    dialog.addEventListener("close", () => {
      const url = new URL(window.location.href)
      if (url.searchParams.has("ajouter")) {
        url.searchParams.delete("ajouter")
        window.history.replaceState(null, "", url)
      }
    })
  })

  // Opened by the server (no JavaScript at the time, or a form sent back):
  // make it modal so the page behind is inert.
  document.querySelectorAll("dialog[data-dialog][open]").forEach((dialog) => {
    if (typeof dialog.showModal !== "function") return
    dialog.close()
    dialog.showModal()
  })
}

function close(dialog) {
  dialog.close()
}
