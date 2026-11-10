// The table of stock exchanges filters as you type. Without JavaScript the
// search form is submitted and the server filters (same result, same URL).
const normalize = (s) => s.normalize("NFD").replace(/\p{Mn}/gu, "").toLowerCase()

export function initMarketSearch() {
  const input = document.querySelector("[data-market-search]")
  const table = document.getElementById("market-list")
  if (!input || !table) return

  const rows = Array.from(table.tBodies[0].rows)
  const count = document.getElementById("market-count")
  const empty = document.getElementById("market-none-live")
  const form = input.form

  const apply = () => {
    const q = normalize(input.value.trim())
    let shown = 0
    for (const row of rows) {
      const hit = !q || (row.dataset.search || "").includes(q)
      row.hidden = !hit
      if (hit) shown++
    }
    if (count) {
      const template = q ? (shown === 1 ? count.dataset.one : count.dataset.many) : count.dataset.all
      // Every form of the line starts with its number (« 2 results… », « 2 résultats… »).
      count.textContent = template.replace(/^\d+/, shown).replace("__Q__", input.value.trim())
    }
    if (empty) empty.hidden = shown !== 0
    // Keep the address in step, so the filtered list can be shared.
    const url = new URL(window.location.href)
    if (input.value.trim()) url.searchParams.set("q", input.value.trim())
    else url.searchParams.delete("q")
    window.history.replaceState(null, "", url)
  }

  input.addEventListener("input", apply)
  form?.addEventListener("submit", (e) => { e.preventDefault(); apply() })
}
