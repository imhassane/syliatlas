// Amounts in the reader's currency (SyliAtlasWeb.Money, canvas « Sélecteur de
// devise »). The server writes each amount as published, in a
// <span data-money data-currency [data-year]>; this rewrites them in the
// currency chosen in the header menu, the published amount under it.
//
//   * auto (default): the currency of the reader's country, asked once per
//     visit at /visitor (Cloudflare's header), as for the language;
//   * a code: the reader's choice, kept on the device, wins;
//   * "ORIG": every amount as published.
//
// An annual amount (data-year) uses the average rate of its year, and stays
// as published when we have none; others use the latest rate. Rates come
// with the page (units per US dollar): nothing is fetched but the country.
// The budget pages' own « Show amounts in » selects share the same choice.

const KEY = "sa.currency"
const VISITOR = "sa.visitor"
const SYMBOLS = {EUR: "€", USD: "$", CNY: "¥"}
const BILLION = {fr: "Md", es: "mil M", pt: "mil M", ar: "مليار", hi: "अरब", zh: "十亿"}
const MILLION = {fr: "M", es: "M", pt: "M", ar: "مليون", hi: "मिलियन", zh: "百万"}

function read(store, key) {
  try { return store.getItem(key) } catch (_e) { return null }
}

function write(store, key, value) {
  try {
    if (value === null) store.removeItem(key)
    else store.setItem(key, value)
  } catch (_e) { /* private mode: this page only */ }
}

export function short(amount, currency, locale) {
  const base = (locale || "en").slice(0, 2)
  let value = amount
  let unit = null
  if (Math.abs(amount) >= 1e9) { value = amount / 1e9; unit = BILLION[base] || "bn" }
  else if (Math.abs(amount) >= 1e6) { value = amount / 1e6; unit = MILLION[base] || "m" }
  const decimals = Math.abs(value) >= 100 ? 0 : Math.abs(value) >= 10 ? 1 : 2
  const number = new Intl.NumberFormat(base, {minimumFractionDigits: decimals, maximumFractionDigits: decimals})
    .format(value).replace(/^-/, "−")
  return [number, unit, SYMBOLS[currency] || currency].filter(Boolean).join(" ")
}

function rate(table, code) {
  if (code === "USD") return 1
  const r = parseFloat(table && table[code])
  return Number.isFinite(r) && r > 0 ? r : null
}

// Rewrites every amount in `code` (null: as the server wrote them).
function apply(code, data, locale) {
  document.querySelectorAll("[data-money]").forEach(el => {
    const main = el.querySelector("[data-money-main]")
    const local = el.querySelector("[data-money-local]")
    if (!main) return
    if (!("served" in el.dataset)) el.dataset.served = main.textContent
    if (local && !("servedLocal" in el.dataset)) el.dataset.servedLocal = local.textContent
    const restore = () => {
      main.textContent = el.dataset.served
      if (local) { local.textContent = el.dataset.servedLocal; local.hidden = !el.dataset.servedLocal }
    }
    const amount = parseFloat(el.dataset.money)
    const from = el.dataset.currency
    if (!code || !Number.isFinite(amount)) return restore()

    const original = short(amount, from, locale)
    if (code === "ORIG" || code === from) {
      main.textContent = original
      if (local) local.hidden = true
      return
    }

    const table = el.dataset.year ? data.years[el.dataset.year] : data.rates
    const a = rate(table, from)
    const b = rate(table, code)
    if (a === null || b === null) {
      // No rate for that year: as published, said once in the tooltip.
      main.textContent = original
      if (local) local.hidden = true
      el.title = data.noRate || ""
      return
    }
    el.removeAttribute("title")
    main.textContent = short(amount / a * b, code, locale)
    if (local) { local.textContent = original; local.hidden = false }
  })
}

async function visitorCurrency() {
  const cached = read(sessionStorage, VISITOR)
  if (cached) { try { return JSON.parse(cached) } catch (_e) { /* ask again */ } }
  try {
    const response = await fetch("/visitor", {credentials: "omit"})
    if (!response.ok) return {}
    const visitor = await response.json()
    write(sessionStorage, VISITOR, JSON.stringify(visitor))
    return visitor
  } catch (_e) {
    return {}
  }
}

export function initMoney() {
  const menu = document.querySelector("[data-currency-menu]")
  const selects = [...document.querySelectorAll("[data-money-picker]")]
  const source = (menu || selects[0])?.querySelector("script[data-money-rates]")
  if (!source) return

  let data
  try { data = JSON.parse(source.textContent) } catch (_e) { return }
  if (!data || !data.rates) return
  data.years = data.years || {}
  data.noRate = menu?.dataset.noRate
  const locale = document.documentElement.lang
  const known = new Set(["ORIG", "USD", ...Object.keys(data.rates)])

  let autoCurrency = null
  const choice = () => {
    const stored = read(localStorage, KEY)
    return stored && known.has(stored) ? stored : null
  }
  const effective = () => choice() || autoCurrency

  const render = () => {
    const code = effective()
    apply(code, data, locale)
    menu?.update(choice(), code)
    selects.forEach(p => {
      const s = p.querySelector("select")
      if (code && [...s.options].some(o => o.value === code)) s.value = code
    })
  }

  const choose = code => {
    write(localStorage, KEY, code)
    render()
  }

  selects.forEach(p => {
    // The header menu does the same on every page: the budget selects stay
    // only where it is missing.
    if (menu) return
    p.hidden = false
    p.querySelector("select").addEventListener("change", e => choose(e.target.value))
  })

  if (menu) setupMenu(menu, choose)
  render()

  if (!choice()) {
    visitorCurrency().then(visitor => {
      menu?.detected(visitor, locale)
      if (visitor.country) autoCurrency = visitor.currency && known.has(visitor.currency) ? visitor.currency : "USD"
      render()
    })
  } else {
    // Still name the reader's country in the « Auto » row.
    visitorCurrency().then(visitor => menu?.detected(visitor, locale))
  }
}

// The header menu: a button, a searchable list of ten rows that scrolls.
function setupMenu(root, choose) {
  const button = root.querySelector(".cur-btn")
  const pop = root.querySelector(".cur-pop")
  const search = root.querySelector(".cur-search")
  const list = root.querySelector(".cur-list")
  const empty = root.querySelector(".cur-empty")
  const options = [...list.querySelectorAll("[role=option]")]
  const heads = [...list.querySelectorAll(".cur-head")]
  const auto = list.querySelector("[data-value=auto]")
  const label = root.querySelector("[data-cur-label]")
  const mark = root.querySelector("[data-cur-mark]")
  let active = null

  root.hidden = false
  const visible = () => options.filter(o => !o.hidden)
  const norm = text => (text || "").toLowerCase().normalize("NFD").replace(/\p{Diacritic}/gu, "")

  const highlight = option => {
    active?.classList.remove("is-active")
    active = option || null
    if (!active) return search.removeAttribute("aria-activedescendant")
    active.classList.add("is-active")
    search.setAttribute("aria-activedescendant", active.id)
    active.scrollIntoView({block: "nearest"})
  }

  const filter = () => {
    const q = norm(search.value.trim())
    options.forEach(o => { o.hidden = q !== "" && !norm(o.dataset.search).includes(q) })
    heads.forEach(h => { h.hidden = q !== "" })
    empty.hidden = visible().length > 0
    if (!active || active.hidden) highlight(visible()[0])
  }

  const open = () => {
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
    if (focus) button.focus()
  }

  const pick = option => {
    const value = option.dataset.value
    choose(value === "auto" ? null : value)
    close()
  }

  button.addEventListener("click", () => (pop.hidden ? open() : close()))
  search.addEventListener("input", filter)
  search.addEventListener("keydown", event => {
    const shown = visible()
    const i = shown.indexOf(active)
    const keys = {
      ArrowDown: () => highlight(shown[Math.min(i + 1, shown.length - 1)]),
      ArrowUp: () => highlight(shown[Math.max(i - 1, 0)]),
      Home: () => highlight(shown[0]),
      End: () => highlight(shown[shown.length - 1]),
      Enter: () => active && pick(active),
      Escape: () => close()
    }
    if (keys[event.key]) { event.preventDefault(); keys[event.key]() }
    else if (event.key === "Tab") close(false)
  })
  list.addEventListener("click", event => {
    const option = event.target.closest("[role=option]")
    if (option) pick(option)
  })
  list.addEventListener("mousemove", event => {
    const option = event.target.closest("[role=option]")
    if (option && option !== active) highlight(option)
  })
  document.addEventListener("click", event => { if (!root.contains(event.target)) close(false) })

  // chosen: the stored choice (null: auto); shown: the currency in use.
  root.update = (chosen, shown) => {
    options.forEach(o => o.setAttribute("aria-selected", String(o.dataset.value === (chosen || "auto"))))
    const option = options.find(o => o.dataset.value === (shown || "ORIG"))
    label.textContent = option ? option.dataset.short : ""
    const m = option?.querySelector(".cur-mark")
    mark.replaceChildren(...(m ? [...m.cloneNode(true).childNodes] : []))
  }

  root.detected = (visitor, locale) => {
    if (!auto) return
    const sub = auto.querySelector("[data-auto-sub]")
    const name = auto.querySelector("[data-auto-name]")
    const autoMark = auto.querySelector(".cur-mark")
    if (!visitor.country) { sub.textContent = root.dataset.noCountry; return }
    let country = visitor.country
    try { country = new Intl.DisplayNames([locale], {type: "region"}).of(visitor.country) } catch (_e) { /* code */ }
    const code = visitor.currency || "USD"
    const option = options.find(o => o.dataset.value === code)
    if (option) {
      name.textContent = option.dataset.name
      autoMark.replaceChildren(...[...option.querySelector(".cur-mark").cloneNode(true).childNodes])
    }
    sub.textContent = (visitor.currency ? root.dataset.yourCountry : root.dataset.notTracked).replace("%{country}", country)
  }
}
