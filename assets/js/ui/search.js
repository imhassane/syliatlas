// Suggestions under every search field (header, home, search page).
// Without JavaScript the form submits to the search page, which gives the
// same results: this only saves a page load. The field is an ARIA combobox:
// arrows move, Enter opens, Escape closes, « / » focuses the header field.

const DELAY = 120

export function initSearch() {
  const forms = document.querySelectorAll("form[data-search]")
  forms.forEach(setup)

  // The Themes menu is a <details>: close it on a click elsewhere or Escape.
  const menus = document.querySelectorAll("[data-nav-menu]")
  document.addEventListener("click", (e) => {
    menus.forEach((m) => { if (m.open && !m.contains(e.target)) m.open = false })
  })
  document.addEventListener("keydown", (e) => {
    if (e.key !== "Escape") return
    menus.forEach((m) => {
      if (m.open) {
        m.open = false
        m.querySelector("summary")?.focus()
      }
    })
  })

  document.addEventListener("keydown", (e) => {
    if (e.key !== "/" || e.defaultPrevented || e.metaKey || e.ctrlKey || e.altKey) return
    const t = e.target
    if (t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName))) return
    const input = document.querySelector("[data-shortcut='/']")
    if (input && input.offsetParent !== null) {
      e.preventDefault()
      input.focus()
      input.select()
    }
  })
}

function setup(form) {
  const input = form.querySelector("[data-search-input]")
  const list = form.querySelector("[data-search-list]")
  if (!input || !list) return

  const locale = form.dataset.search
  let timer = null
  let controller = null
  let items = []
  let active = -1
  let last = ""

  const close = () => {
    list.hidden = true
    input.setAttribute("aria-expanded", "false")
    input.removeAttribute("aria-activedescendant")
    active = -1
  }

  const highlight = (i) => {
    items.forEach((el, j) => el.setAttribute("aria-selected", j === i ? "true" : "false"))
    active = i
    if (i >= 0 && items[i]) input.setAttribute("aria-activedescendant", items[i].id)
    else input.removeAttribute("aria-activedescendant")
  }

  const option = (id, href, main, side, extra) => {
    const a = document.createElement("a")
    a.id = id
    a.href = href
    a.className = "search-option" + (extra ? " " + extra : "")
    a.setAttribute("role", "option")
    a.setAttribute("aria-selected", "false")
    const b = document.createElement("span")
    b.textContent = main
    a.appendChild(b)
    if (side) {
      const s = document.createElement("span")
      s.className = "search-kind"
      s.textContent = side
      a.appendChild(s)
    }
    return a
  }

  const render = (data) => {
    list.replaceChildren()
    const base = input.id + "-opt-"
    let n = 0
    const a = data.answer
    if (a) {
      const el = option(base + n++, a.path, `${a.name} · ${a.label} ${a.year} : ${a.value}`, a.source, "search-answer")
      list.appendChild(el)
    }
    for (const r of data.results.slice(0, 8)) {
      list.appendChild(option(base + n++, r.path, r.label, r.kind))
    }
    if (n === 0) {
      const p = document.createElement("p")
      p.className = "search-empty"
      p.textContent = list.dataset.empty || form.dataset.empty || "—"
      list.appendChild(p)
    }
    items = Array.from(list.querySelectorAll("[role=option]"))
    list.hidden = false
    input.setAttribute("aria-expanded", "true")
    highlight(-1)
  }

  const fetchResults = async (q) => {
    if (controller) controller.abort()
    controller = new AbortController()
    try {
      const url = `/api/v1/search?locale=${encodeURIComponent(locale)}&q=${encodeURIComponent(q)}`
      const res = await fetch(url, {signal: controller.signal, headers: {accept: "application/json"}})
      if (!res.ok) return
      const data = await res.json()
      if (input.value.trim() === q) render(data)
    } catch (_e) {
      // Offline or aborted: the form still submits to the search page.
    }
  }

  input.addEventListener("input", () => {
    const q = input.value.trim()
    clearTimeout(timer)
    if (q.length < 2) {
      last = q
      close()
      return
    }
    if (q === last) return
    last = q
    timer = setTimeout(() => fetchResults(q), DELAY)
  })

  input.addEventListener("keydown", (e) => {
    if (list.hidden) return
    if (e.key === "ArrowDown") {
      e.preventDefault()
      highlight(Math.min(active + 1, items.length - 1))
    } else if (e.key === "ArrowUp") {
      e.preventDefault()
      highlight(Math.max(active - 1, -1))
    } else if (e.key === "Enter" && active >= 0 && items[active]) {
      e.preventDefault()
      window.location.href = items[active].href
    } else if (e.key === "Escape") {
      e.preventDefault()
      close()
    }
  })

  input.addEventListener("focus", () => {
    if (items.length && input.value.trim().length >= 2) {
      list.hidden = false
      input.setAttribute("aria-expanded", "true")
    }
  })

  document.addEventListener("click", (e) => {
    if (!form.contains(e.target)) close()
  })
}
