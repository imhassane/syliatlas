// Budget amounts in the reader's currency (SyliAtlasWeb.BudgetComponents).
// The server writes them in the language's default currency (euro in
// French, dollar elsewhere), the local amount under them; this rewrites
// them in the currency picked in « Show amounts in », kept in the browser.
// Rates come with the page (units per US dollar), so nothing is fetched.
// Same short form as SyliAtlas.Budgets.Money: « 6,09 Md € », « 233 M € ».

const KEY = "sa.currency"
const SYMBOLS = {EUR: "€", USD: "$"}
const BILLION = {fr: "Md", es: "mil M", pt: "mil M", ar: "مليار", hi: "अरब", zh: "十亿"}
const MILLION = {fr: "M", es: "M", pt: "M", ar: "مليون", hi: "मिलियन", zh: "百万"}

function read() {
  try { return localStorage.getItem(KEY) } catch (_e) { return null }
}

function save(code) {
  try { localStorage.setItem(KEY, code) } catch (_e) { /* private mode: this page only */ }
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

function rate(rates, code) {
  if (code === "USD") return 1
  const r = parseFloat(rates[code])
  return Number.isFinite(r) && r > 0 ? r : null
}

function apply(code, rates, locale) {
  document.querySelectorAll("[data-money]").forEach(el => {
    const amount = parseFloat(el.dataset.money)
    const from = el.dataset.currency
    const main = el.querySelector("[data-money-main]")
    const local = el.querySelector("[data-money-local]")
    const a = rate(rates, from)
    const b = rate(rates, code)
    if (!main || !Number.isFinite(amount)) return
    if (code === from || a === null || b === null) {
      main.textContent = short(amount, from, locale)
      if (local) local.hidden = true
    } else {
      main.textContent = short(amount / a * b, code, locale)
      if (local) local.hidden = false
    }
  })
}

export function initMoney() {
  const pickers = document.querySelectorAll("[data-money-picker]")
  if (!pickers.length) return

  const data = pickers[0].querySelector("script[data-money-rates]")
  let rates = {}
  try { rates = JSON.parse(data.textContent).rates || {} } catch (_e) { return }

  const select = pickers[0].querySelector("select")
  const locale = select.dataset.locale || document.documentElement.lang
  const stored = read()
  const options = s => Array.from(s.options).map(o => o.value)

  pickers.forEach(picker => {
    const s = picker.querySelector("select")
    picker.hidden = false
    if (stored && options(s).includes(stored)) s.value = stored
    s.addEventListener("change", () => {
      save(s.value)
      pickers.forEach(p => { p.querySelector("select").value = s.value })
      apply(s.value, rates, locale)
    })
  })

  if (stored && stored !== select.dataset.default && options(select).includes(stored)) {
    apply(stored, rates, locale)
  }
}
