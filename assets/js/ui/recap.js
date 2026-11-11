// The recap subscription dialog (Layouts.recap_dialog). The footer's band
// (an address and « Choose my countries ») leads to the recap page; with
// this script it opens the dialog instead, the address filled in, posts the
// same form as JSON and shows the second step. The country of the page (its
// « Follow » star) comes pre-checked. The recap page's own form is enhanced
// by initRecapPage below.

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

  const open = (email) => {
    const star = document.querySelector('[data-favorite^="area:"]')
    if (star) check(star.dataset.favorite.slice(5))
    showError("")
    step(1)
    const field = form.querySelector("input[type=email]")
    if (email) field.value = email
    dialog.showModal()
    // The address is there already: go on with the countries.
    if (field.value) chips.querySelector("input")?.focus()
    else field.focus()
  }

  // The footer band: its address goes into the dialog.
  document.querySelectorAll("form[data-recap-start]").forEach((start) => {
    start.addEventListener("submit", (event) => {
      event.preventDefault()
      open(start.querySelector("input[type=email]").value.trim())
    })
  })

  document.querySelectorAll("a[data-recap-open]").forEach((link) => {
    link.addEventListener("click", (event) => {
      event.preventDefault()
      open("")
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

// The recap page and its « change » page (RecapHTML): the region tabs show
// one region at a time, and the bottom bar follows what is chosen. Without
// this script, every region shows and the bar says what the server saw.
export function initRecapPage() {
  const form = document.querySelector("form[data-recap-page]")
  if (!form) return

  const tabs = form.querySelector("[data-recap-tabs]")
  const regions = form.querySelectorAll(".recap-region[data-region]")
  if (tabs) {
    tabs.hidden = false
    tabs.addEventListener("click", (event) => {
      const tab = event.target.closest("button[data-region]")
      if (!tab) return
      tabs.querySelectorAll("button").forEach((b) => b.setAttribute("aria-pressed", String(b === tab)))
      regions.forEach((r) => (r.hidden = tab.dataset.region !== "" && r.dataset.region !== tab.dataset.region))
    })
  }

  const bar = form.querySelector("[data-recap-summary]")
  if (!bar) return
  const max = Number(bar.dataset.max)

  const update = () => {
    const picked = [...form.querySelectorAll("input[name='countries[]']:checked")]
    bar.querySelector("[data-recap-names]").textContent =
      picked.length ? picked.map((i) => i.nextElementSibling.textContent).join(", ") : bar.dataset.none
    bar.querySelector("[data-recap-count]").textContent = picked.length
    const frequency = form.querySelector("input[name=frequency]:checked")
    if (frequency) bar.querySelector("[data-recap-frequency]").textContent = frequency.dataset.label
    // Past the limit, the other countries wait: the server refuses more anyway.
    form.querySelectorAll("input[name='countries[]']:not(:checked)").forEach((i) => (i.disabled = picked.length >= max))
  }

  form.addEventListener("change", update)
  update()
}
