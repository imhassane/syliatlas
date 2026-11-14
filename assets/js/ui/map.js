// The home map (MapComponents.map_section/1).
//
// Without JavaScript each country links to its profile. Here a click shows
// the country in the panel instead (a bottom sheet on phones), the
// indicator switch recolours the map, and the arrows walk the ranking.

import {moneySpan, refreshMoney} from "./money"

const phone = matchMedia("(max-width: 39.99rem)")

export function initMap() {
  const root = document.querySelector("[data-map]")
  const dataEl = document.getElementById("map-data")
  if (!root || !dataEl) return

  const data = JSON.parse(dataEl.textContent)
  const panel = document.getElementById("map-panel")
  const svg = root.querySelector(".map")
  const legend = root.querySelector("[data-map-legend]")
  const goto = root.querySelector("[data-map-goto]")
  const field = name => panel.querySelector(`[data-field="${name}"]`)
  let selected = root.dataset.selected
  let indicator = root.dataset.indicator
  // Home hero: the panel is a <dialog>, a modal drawer below 64rem.
  const isDialog = panel.tagName === "DIALOG"
  const drawer = root.dataset.drawer ? matchMedia(root.dataset.drawer) : phone
  let opener = null
  let quiet = false // closing to re-lay the dialog: no focus move

  function setIndicator(key) {
    indicator = key
    root.dataset.indicator = key
    svg.querySelectorAll(".cty").forEach(a => {
      const c = data.countries[a.dataset.code]
      if (!c) return
      a.classList.forEach(cls => cls.startsWith("q-") && a.classList.remove(cls))
      a.classList.add(c.classes[key])
      a.setAttribute("aria-label", `${a.dataset.name} : ${c.values[key]}`)
    })
    root.querySelectorAll("[data-map-indicator]").forEach(link => {
      if (link.dataset.mapIndicator === key) link.setAttribute("aria-current", "true")
      else link.removeAttribute("aria-current")
    })
    const entries = data.indicators[key].legend
      .map(([cls, label]) => `<li><i class="${cls}"></i>${escapeHtml(label)}</li>`)
      .join("")
    const noData = legend.lastElementChild.outerHTML
    legend.innerHTML = entries + noData
    fillIndicatorPill()
  }

  function fillIndicatorPill() {
    const c = data.countries[selected]
    field("indicator").textContent = `${data.indicators[indicator].title} : ${c.values[indicator]}`
  }

  function select(code, {open = true} = {}) {
    const c = data.countries[code]
    if (!c) return
    svg.querySelector(".cty.is-sel")?.classList.remove("is-sel")
    svg.querySelector(`.cty[data-code="${code}"]`)?.classList.add("is-sel")
    selected = code

    field("name").textContent = c.name
    field("meta").textContent = c.meta
    const gdp = field("gdp")
    setMoney(gdp, c.gdp, data.to, c.text.gdp)
    for (const [name, key] of [["gdp-change", "gdp_change"]]) {
      const el = field(name)
      el.textContent = c.text[key]
      el.classList.remove("up", "down")
      if (c.tones[key]) el.classList.add(c.tones[key])
    }
    for (const key of ["gdppc", "growth", "inflation", "debt"]) field(key).textContent = c.text[key]
    fillRating(c.rating)
    fillNational(c)
    field("href").href = c.href
    field("name-vh").textContent = ` : ${c.name}`
    field("name-vh-compare").textContent = ` : ${c.name}`
    field("compare").href = c.compare
    fillIndicatorPill()
    drawSpark(c.series)
    if (goto) goto.value = c.name

    // Replay the entrance of the panel's content (the figures appear at once).
    const body = panel.querySelector("[data-map-body]")
    body.classList.remove("is-entering")
    void body.offsetWidth
    body.classList.add("is-entering")

    if (!open) return
    if (isDialog) showDialog()
    else if (drawer.matches && panel.showPopover && !panel.matches(":popover-open")) panel.showPopover()
  }

  // Home hero (a <dialog>): from 64rem the country takes the place of the
  // left column; below, a modal drawer (the page behind is inert, Escape
  // closes it). Either way focus goes to the country's name, and back to
  // the country (or the list) when it closes.
  function showDialog() {
    if (drawer.matches) {
      if (panel.matches(":modal")) return
      opener = document.activeElement
      if (panel.open) shut()
      panel.showModal()
    } else {
      if (panel.open) return
      opener = document.activeElement
      panel.show()
    }
    field("name").focus({preventScroll: drawer.matches})
    if (!drawer.matches) panel.scrollIntoView({block: "nearest"})
  }

  // On resize, a drawer left open becomes the column, and back.
  function layDialog() {
    if (!isDialog || !panel.open) return
    if (drawer.matches && !panel.matches(":modal")) shut()
    else if (!drawer.matches && panel.matches(":modal")) { shut(); panel.show() }
  }

  function shut() {
    if (!panel.open) return
    // The close event comes later (a task): the handler resets the flag.
    quiet = true
    panel.close()
  }

  if (isDialog) {
    // A country asked in the URL: in the column, never a drawer at load.
    if (drawer.matches) shut()
    drawer.addEventListener("change", layDialog)
    panel.querySelectorAll("[data-map-close]").forEach(button => button.addEventListener("click", () => panel.close()))
    // Escape also closes the column (the modal drawer does it natively).
    panel.addEventListener("keydown", event => {
      if (event.key === "Escape" && !panel.matches(":modal")) { event.preventDefault(); panel.close() }
    })
    // A tap on the backdrop (the dialog box itself, outside its content).
    panel.addEventListener("click", event => {
      if (event.target !== panel || !panel.matches(":modal")) return
      const r = panel.getBoundingClientRect()
      const inside = event.clientX >= r.left && event.clientX <= r.right && event.clientY >= r.top && event.clientY <= r.bottom
      if (!inside) panel.close()
    })
    panel.addEventListener("close", () => {
      if (quiet) { quiet = false; return }
      const back = svg.querySelector(`.cty[data-code="${selected}"]`)
      // Back to the list if the country was chosen there, else to the country.
      const target = opener && opener === goto ? goto : back
      target?.focus()
      opener = null
    })
  }

  // A GDP in billions of dollars the currency menu rewrites.
  function setMoney(el, billions, year, text) {
    if (typeof billions !== "number") { el.textContent = text; return }
    el.replaceChildren(moneySpan(billions * 1e9, "USD", year, text))
    refreshMoney()
  }

  // The country's latest official GDP (MapComponents.national_text/3).
  function fillNational(c) {
    if (!field("national")) return
    const n = c.national
    for (const name of ["national-value", "national-period"]) field(name).hidden = !n
    // Only a figure being checked carries a badge.
    field("national-status").hidden = !(n && n.status)
    field("national-none").hidden = !!n
    const label = field("gdp-label")
    if (label && c.gdp_label) label.textContent = "short" in label.dataset ? c.gdp_short : c.gdp_label
    if (!n) return
    setMoney(field("national-value"), n.amount, n.year, n.value)
    field("national-period").textContent = n.period
    const status = field("national-status")
    status.textContent = n.status || ""
    status.classList.remove("pill-warn", "pill-ok", "pill-neutral")
    status.classList.add(n.status_class)
  }

  // The country's sovereign rating (MapComponents.rating_text/2).
  function fillRating(rating) {
    if (!rating || !field("rating")) return
    field("rating-label").textContent = rating.label
    const verdict = field("rating-verdict")
    verdict.textContent = rating.verdict
    verdict.classList.forEach(cls => cls.startsWith("rt-") && cls !== "rt-badge" && verdict.classList.remove(cls))
    verdict.classList.add(rating.class)
    field("rating-detail").textContent = rating.detail
  }

  // Same maths as SyliAtlasWeb.Spark.
  function drawSpark(series) {
    const w = 260, h = 56, from = data.from, to = data.to
    const base = series && series[from - 2015]
    const pts = (series || []).map((v, i) => (v != null && base ? [i + 2015, (v / base) * 100] : null)).filter(Boolean)
    const past = field("spark-past"), future = field("spark-future"), dot = field("spark-dot"), baseLine = field("spark-base")
    if (!pts.length) { past.setAttribute("d", ""); future.setAttribute("d", ""); return }
    const vals = pts.map(p => p[1]), lo = Math.min(...vals), hi = Math.max(...vals)
    const x = yr => 4 + ((w - 8) * (yr - 2015)) / 15
    const y = v => h - 4 - ((v - lo) / Math.max(hi - lo, 1)) * (h - 8)
    const path = list => (list.length ? "M" + list.map(([yr, v]) => `${x(yr).toFixed(1)} ${y(v).toFixed(1)}`).join(" L") : "")
    past.setAttribute("d", path(pts.filter(p => p[0] <= 2025)))
    future.setAttribute("d", path(pts.filter(p => p[0] >= 2025)))
    const end = pts.find(p => p[0] === to)
    if (dot && end) { dot.setAttribute("cx", x(end[0]).toFixed(1)); dot.setAttribute("cy", y(end[1]).toFixed(1)) }
    if (baseLine) { baseLine.setAttribute("x1", x(from).toFixed(1)); baseLine.setAttribute("x2", x(from).toFixed(1)) }
    // Replay the line drawing.
    const line = field("spark-line")
    line.style.animation = "none"; void line.getBoundingClientRect(); line.style.animation = ""
  }

  svg.addEventListener("click", event => {
    const link = event.target.closest(".cty")
    if (!link || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button !== 0) return
    event.preventDefault()
    select(link.dataset.code)
  })

  root.querySelectorAll("[data-map-indicator]").forEach(link =>
    link.addEventListener("click", event => {
      event.preventDefault()
      setIndicator(link.dataset.mapIndicator)
    })
  )

  panel.querySelectorAll("[data-map-step]").forEach(button =>
    button.addEventListener("click", () => {
      const order = data.order
      const i = order.indexOf(selected)
      select(order[(i + Number(button.dataset.mapStep) + order.length) % order.length], {open: false})
    })
  )

  if (goto) {
    goto.addEventListener("change", () => {
      const code = goto.selectedOptions[0]?.dataset.code
      if (code) select(code)
    })
  }
}

function escapeHtml(text) {
  return text.replace(/[&<>"]/g, ch => ({"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;"})[ch])
}
