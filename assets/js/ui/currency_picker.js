// Currency choices of the converter (SyliAtlasWeb.CurrencyHTML.currency_picker):
// the plain select stays for the form and for pages without JavaScript; here
// it is replaced by a button opening a searchable list of ten rows that
// scrolls. Choosing a currency converts at once.
const asSheet = matchMedia("(max-width: 560px)")

export function initCurrencyPickers() {
  const pickers = [...document.querySelectorAll("[data-currency-picker]")]
  pickers.forEach(setup)

  // Swapping the two currencies needs no page load either.
  document.querySelectorAll("[data-fx-swap]").forEach(link => {
    const form = link.closest("form")
    const [a, b] = form ? [...form.querySelectorAll("[data-currency-picker]")] : []
    if (!a || !b) return
    link.addEventListener("click", event => {
      event.preventDefault()
      const from = a.querySelector("select").value
      const to = b.querySelector("select").value
      a.choose(to, false)
      b.choose(from, false)
      form.requestSubmit()
    })
  })
}

function setup(root) {
  const select = root.querySelector("select")
  const ui = root.querySelector(".fx-pick-ui")
  const button = root.querySelector(".fx-pick-btn")
  const pop = root.querySelector(".fx-pick-pop")
  const search = root.querySelector(".fx-pick-search")
  const list = root.querySelector(".fx-pick-list")
  const empty = root.querySelector(".fx-pick-empty")
  const options = [...list.querySelectorAll("[role=option]")]
  const label = root.querySelector("label")
  let active = null
  let backdrop = null

  select.hidden = true
  ui.hidden = false
  if (label) label.htmlFor = ""
  label?.addEventListener("click", () => button.focus())

  const visible = () => options.filter(o => !o.hidden)

  const highlight = option => {
    active?.classList.remove("is-active")
    active = option
    if (!option) return search.removeAttribute("aria-activedescendant")
    option.classList.add("is-active")
    search.setAttribute("aria-activedescendant", option.id)
    option.scrollIntoView({block: "nearest"})
  }

  const open = () => {
    // On a phone: a sheet at the bottom of the screen, above a backdrop.
    if (asSheet.matches) {
      backdrop = document.createElement("div")
      backdrop.className = "fx-pick-backdrop"
      backdrop.addEventListener("click", () => close())
      document.body.append(backdrop, pop)
      pop.classList.add("is-sheet")
    }
    pop.hidden = false
    button.setAttribute("aria-expanded", "true")
    search.value = ""
    filter()
    highlight(options.find(o => o.getAttribute("aria-selected") === "true") || visible()[0])
    search.focus({preventScroll: true})
  }

  const close = (focus = true) => {
    if (pop.hidden) return
    pop.hidden = true
    button.setAttribute("aria-expanded", "false")
    if (pop.classList.contains("is-sheet")) {
      pop.classList.remove("is-sheet")
      backdrop?.remove()
      backdrop = null
      ui.append(pop)
    }
    if (focus) button.focus()
  }

  const filter = () => {
    const q = search.value.trim().toLowerCase().normalize("NFD").replace(/\p{Diacritic}/gu, "")
    options.forEach(o => {
      const text = o.dataset.search.normalize("NFD").replace(/\p{Diacritic}/gu, "")
      o.hidden = q !== "" && !text.includes(q)
    })
    empty.hidden = visible().length > 0
    if (active?.hidden) highlight(visible()[0])
  }

  root.choose = (value, submit = true) => {
    const option = options.find(o => o.dataset.value === value)
    if (!option) return
    select.value = value
    options.forEach(o => o.setAttribute("aria-selected", String(o === option)))
    const current = root.querySelector("[data-current]")
    const mark = option.querySelector(".fx-flags").cloneNode(true)
    const code = document.createElement("b")
    code.textContent = value
    const name = document.createElement("span")
    name.className = "fx-pick-name"
    name.textContent = option.querySelector(".fx-pick-text b").textContent
    current.replaceChildren(mark, code, name)
    if (submit) {
      close()
      select.form?.requestSubmit()
    }
  }

  button.addEventListener("click", () => (pop.hidden ? open() : close()))
  search.addEventListener("input", filter)

  search.addEventListener("keydown", event => {
    const shown = visible()
    const i = shown.indexOf(active)
    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        highlight(shown[Math.min(i + 1, shown.length - 1)])
        break
      case "ArrowUp":
        event.preventDefault()
        highlight(shown[Math.max(i - 1, 0)])
        break
      case "Home":
        event.preventDefault()
        highlight(shown[0])
        break
      case "End":
        event.preventDefault()
        highlight(shown[shown.length - 1])
        break
      case "Enter":
        event.preventDefault()
        if (active) root.choose(active.dataset.value)
        break
      case "Escape":
        event.preventDefault()
        close()
        break
      case "Tab":
        close(false)
        break
    }
  })

  list.addEventListener("click", event => {
    const option = event.target.closest("[role=option]")
    if (option) root.choose(option.dataset.value)
  })

  list.addEventListener("mousemove", event => {
    const option = event.target.closest("[role=option]")
    if (option && option !== active) highlight(option)
  })

  document.addEventListener("click", event => {
    if (!root.contains(event.target) && !pop.contains(event.target)) close(false)
  })
}
