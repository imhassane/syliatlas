// The recap subscription dialog (Layouts.recap_dialog). The footer's
// « Get the recap » link leads to the recap page; with this script it opens
// the dialog instead, posts the same form as JSON and shows the second
// step. The country of the page (its « Follow » star) comes pre-checked.

export function initRecap() {
  const dialog = document.getElementById("recap-dialog")
  if (!dialog || typeof dialog.showModal !== "function") return

  const form = dialog.querySelector("[data-recap-form]")
  const sent = document.getElementById("recap-dialog-sent")
  const error = document.getElementById("recap-dialog-error")
  const chips = dialog.querySelector("[data-recap-chips]")
  const add = dialog.querySelector("[data-recap-add]")
  const steps = dialog.querySelectorAll("[data-recap-step]")

  const check = (code) => {
    if (!code) return
    let input = chips.querySelector(`input[value="${CSS.escape(code)}"]`)
    if (!input) {
      const option = add.querySelector(`option[value="${CSS.escape(code)}"]`)
      if (!option) return
      const label = document.createElement("label")
      label.className = "recap-chip"
      input = document.createElement("input")
      input.type = "checkbox"
      input.name = "countries[]"
      input.value = code
      const span = document.createElement("span")
      span.textContent = option.textContent
      label.append(input, span)
      chips.append(label)
    }
    input.checked = true
  }

  const step = (n) => {
    steps.forEach((li) => {
      const i = Number(li.dataset.recapStep)
      if (i === n) li.setAttribute("aria-current", "step")
      else li.removeAttribute("aria-current")
      li.classList.toggle("done", i < n)
    })
    form.hidden = n !== 1
    sent.hidden = n !== 2
  }

  const showError = (message) => {
    error.textContent = message
    error.hidden = !message
  }

  document.querySelectorAll("[data-recap-open]").forEach((link) => {
    link.addEventListener("click", (event) => {
      event.preventDefault()
      const star = document.querySelector('[data-favorite^="area:"]')
      if (star) check(star.dataset.favorite.slice(5))
      showError("")
      dialog.showModal()
      if (!form.hidden) form.querySelector("input[type=email]").focus()
    })
  })

  add.addEventListener("change", () => {
    check(add.value)
    add.value = ""
  })

  dialog.querySelectorAll("[data-recap-close]").forEach((b) => b.addEventListener("click", () => dialog.close()))
  dialog.querySelector("[data-recap-again]").addEventListener("click", () => {
    step(1)
    form.querySelector("input[type=email]").focus()
  })

  form.addEventListener("submit", async (event) => {
    event.preventDefault()
    showError("")
    const button = form.querySelector("button[type=submit]")
    button.disabled = true
    try {
      const response = await fetch(form.action, {
        method: "POST",
        headers: {accept: "application/json"},
        body: new FormData(form),
      })
      const body = await response.json()
      if (body.ok) {
        dialog.querySelector("[data-recap-email]").textContent = body.email
        step(2)
        sent.querySelector(".recap-dialog-title").focus()
      } else {
        showError(body.error)
      }
    } catch (_offline) {
      // No answer as JSON: let the browser post the form and show the page.
      form.submit()
    } finally {
      button.disabled = false
    }
  })
}
