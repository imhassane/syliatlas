// Chart tooltips (SyliAtlasWeb.Charts, MarketComponents.index_chart).
//
// The server draws each chart as SVG and writes, in data-chart-tips, what
// every year (or session) shows, already formatted for the page's language:
// position, values, status, change, source. This file only displays it.
//
//   * mouse: the guide line follows the pointer to the nearest year; a click
//     makes that year the end of the period (?to=), as the period form does;
//   * touch: tap or drag to read a year; the reading sits under the chart,
//     never under the finger, with a link to show that year in the figures;
//   * keyboard: one tab stop per chart, a slider (←/→, ↑/↓, Home, End,
//     Page Up/Down); Enter shows the year in the figures; the screen reader
//     reads aria-valuetext, so the visual tooltip is aria-hidden;
//   * Escape closes the tooltip (WCAG 1.4.13); the pointer can move over it.
//
// Without JavaScript the reader stays hidden: no extra tab stop, and the
// table under each chart gives every value.

import {moneySpan, refreshMoney} from "./money"

const SVG_NS = "http://www.w3.org/2000/svg"
const DOCK_BELOW = 520 // px: narrower boxes get the reading under the chart

function svgEl(name, attrs) {
  const el = document.createElementNS(SVG_NS, name)
  for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, v)
  return el
}

function htmlEl(name, className, text) {
  const el = document.createElement(name)
  if (className) el.className = className
  if (text != null) el.textContent = text
  return el
}

function pickHref(data, point) {
  const url = new URL(window.location.href)
  url.searchParams.set("to", point.year)
  if (!url.searchParams.has("from") && data.from) url.searchParams.set("from", data.from)
  url.hash = data.anchor || ""
  return url.toString()
}

function setup(box, data) {
  const svg = box.querySelector("svg")
  const reader = box.querySelector(".chart-reader")
  const tip = box.querySelector(".chart-tip")
  if (!svg || !reader || !tip) return

  const points = data.points
  const last = points.length - 1
  let index = Math.min(Math.max(data.start ?? last, 0), last)
  let open = false
  let via = "mouse" // what moved the reading last: mouse, touch, pen or keyboard

  // The reader covers the drawing only, so a reading docked under the chart
  // stays clickable: it takes the drawing's rendered height.
  const fit = () => { reader.style.height = `${svg.getBoundingClientRect().height}px` }
  reader.hidden = false
  fit()
  if ("ResizeObserver" in window) new ResizeObserver(fit).observe(svg)

  const layer = svgEl("g", {class: "chart-hover", "aria-hidden": "true"})
  layer.style.display = "none"
  const guide = svgEl("line", {class: "chart-hover-line", y1: data.top, y2: data.bottom})
  layer.append(guide)
  const dots = points[0].rows.map((row, k) => {
    const dot = svgEl("circle", {class: "chart-hover-dot", r: k === 0 ? 5.5 : 4.5})
    dot.style.fill = `var(${row.color})`
    layer.append(dot)
    return dot
  })
  svg.append(layer)

  function render(point) {
    const body = htmlEl("div", "chart-tip-body")
    body.setAttribute("aria-hidden", "true")

    const head = htmlEl("p", "chart-tip-head")
    head.append(htmlEl("b", "num", point.title))
    const kinds = {data: "pill-neutral", estimate: "pill-info", projection: "pill-warn"}
    head.append(htmlEl("span", `pill ${kinds[point.kind] || "pill-neutral"}`, point.status))
    body.append(head)

    const list = htmlEl("ul", "chart-tip-rows")
    point.rows.forEach((row, k) => {
      const li = htmlEl("li", k === 0 ? "is-first" : "")
      const swatch = htmlEl("span", "chart-tip-swatch")
      swatch.style.background = `var(${row.color})`
      li.append(swatch, htmlEl("span", "chart-tip-name", row.name), amountEl(row))
      list.append(li)
    })
    // The country's official figure that year, never joined to the series.
    if (point.national) {
      const n = point.national
      const li = htmlEl("li", "chart-tip-national")
      const swatch = htmlEl("span", "chart-tip-diamond")
      li.append(swatch, htmlEl("span", "chart-tip-name", n.label), amountEl(n))
      list.append(li)
      body.append(list)
      // Only a figure being checked carries a badge.
      if (n.wait) body.append(htmlEl("span", "pill pill-warn chart-tip-status", n.status))
    } else {
      body.append(list)
    }

    if (point.change) body.append(htmlEl("p", "chart-tip-change", point.change))
    if (data.source) body.append(htmlEl("p", "chart-tip-src", data.source))
    if (via === "keyboard" && data.keys) body.append(htmlEl("p", "chart-tip-keys", data.keys))

    const parts = [body]
    if (point.pick) {
      const link = htmlEl("a", "chart-tip-pick", point.pick)
      link.href = pickHref(data, point)
      parts.push(link)
    }
    tip.replaceChildren(...parts)
    // Amounts follow the currency chosen in the header.
    if (tip.querySelector("[data-money]")) refreshMoney()
  }

  // An amount in dollars the currency menu can rewrite; anything else as text.
  function amountEl(row) {
    const el = htmlEl("span", "num")
    if (row.money) el.append(moneySpan(row.money.amount, "USD", row.money.year, row.text))
    else el.textContent = row.text
    return el
  }

  function place(point) {
    const docked = box.clientWidth < DOCK_BELOW
    tip.classList.toggle("is-docked", docked)
    if (docked) {
      tip.style.left = ""
      tip.classList.remove("is-flipped")
    } else {
      tip.style.left = `${(point.x / data.w) * 100}%`
      tip.classList.toggle("is-flipped", point.x / data.w > 0.55)
    }

    guide.setAttribute("x1", point.x)
    guide.setAttribute("x2", point.x)
    point.rows.forEach((row, k) => {
      const dot = dots[k]
      if (!dot) return
      if (row.y == null) {
        dot.style.display = "none"
      } else {
        dot.style.display = ""
        dot.setAttribute("cx", point.x)
        dot.setAttribute("cy", row.y)
      }
    })
  }

  function show(i) {
    index = Math.min(Math.max(i, 0), last)
    const point = points[index]
    reader.setAttribute("aria-valuenow", index)
    reader.setAttribute("aria-valuetext", point.valuetext)
    render(point)
    place(point)
    layer.style.display = ""
    tip.hidden = false
    if (!open) {
      open = true
      document.addEventListener("keydown", onDocumentKey, true)
      document.addEventListener("pointerdown", onDocumentPointer, true)
    }
  }

  function hide() {
    if (!open) return
    open = false
    tip.hidden = true
    layer.style.display = "none"
    document.removeEventListener("keydown", onDocumentKey, true)
    document.removeEventListener("pointerdown", onDocumentPointer, true)
  }

  // Escape closes a tooltip opened by hover too, wherever the focus is.
  function onDocumentKey(e) {
    if (e.key === "Escape" && open) {
      hide()
      if (document.activeElement === reader) e.preventDefault()
    }
  }

  // A tap elsewhere closes a reading left open by touch.
  function onDocumentPointer(e) {
    if (!box.contains(e.target)) hide()
  }

  function nearest(clientX) {
    const rect = reader.getBoundingClientRect()
    if (!rect.width) return index
    const x = ((clientX - rect.left) / rect.width) * data.w
    let best = 0
    for (let i = 1; i < points.length; i++) {
      if (Math.abs(points[i].x - x) < Math.abs(points[best].x - x)) best = i
    }
    return best
  }

  reader.addEventListener("pointerdown", e => {
    via = e.pointerType || "mouse"
    if (via !== "mouse") reader.setPointerCapture?.(e.pointerId)
    show(nearest(e.clientX))
  })

  reader.addEventListener("pointermove", e => {
    const type = e.pointerType || "mouse"
    if (type === "mouse" || reader.hasPointerCapture?.(e.pointerId)) {
      via = type
      const i = nearest(e.clientX)
      if (i !== index || !open) show(i)
    }
  })

  // The tooltip sits inside the box: moving onto it keeps it open.
  box.addEventListener("pointerleave", e => {
    if ((e.pointerType || "mouse") === "mouse" && !box.contains(document.activeElement)) hide()
  })

  reader.addEventListener("click", () => {
    const point = points[index]
    if (via === "mouse" && point && point.pick) window.location.assign(pickHref(data, point))
  })

  reader.addEventListener("focus", () => {
    if (reader.matches(":focus-visible")) {
      via = "keyboard"
      show(index)
    }
  })

  box.addEventListener("focusout", e => {
    if (!box.contains(e.relatedTarget)) hide()
  })

  reader.addEventListener("keydown", e => {
    if (e.altKey || e.ctrlKey || e.metaKey) return
    const steps = {
      ArrowRight: 1, ArrowUp: 1, ArrowLeft: -1, ArrowDown: -1,
      PageUp: 5, PageDown: -5
    }
    let next = null
    if (e.key in steps) next = index + steps[e.key]
    else if (e.key === "Home") next = 0
    else if (e.key === "End") next = last
    else if (e.key === "Enter") {
      const point = points[index]
      if (point && point.pick) {
        e.preventDefault()
        window.location.assign(pickHref(data, point))
      }
      return
    } else return

    next = Math.min(Math.max(next, 0), last)
    via = "keyboard"
    // At an end, the key does nothing here: let the page keep it.
    if (next === index && open) return
    e.preventDefault()
    show(next)
  })

  // A resize can move a docked reading back beside the line, or the reverse.
  window.addEventListener("resize", () => { fit(); if (open) place(points[index]) }, {passive: true})
}

export function initChartTips(root = document) {
  root.querySelectorAll("[data-chart-tips]").forEach(box => {
    if (box.dataset.chartTipsReady) return
    box.dataset.chartTipsReady = "true"
    let data
    try {
      data = JSON.parse(box.dataset.chartTips)
    } catch (_e) {
      return
    }
    if (data && Array.isArray(data.points) && data.points.length) setup(box, data)
  })
}
