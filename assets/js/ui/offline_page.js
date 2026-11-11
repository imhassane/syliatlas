// The offline page (PageController.offline): the service worker shows it
// under the asked address when that page is not saved on the device. Fills
// in the asked page's name, the pages saved (read from the cache), how many
// country pages are saved and the last connection; reloads when back online.
const SHOWN = 6

export async function initOfflinePage() {
  const root = document.querySelector("[data-offline-page]")
  const dataEl = document.getElementById("offline-pages")
  if (!root || !dataEl) return
  const {home, pages, strings} = JSON.parse(dataEl.textContent)
  const $ = sel => root.querySelector(sel)

  root.querySelector("[data-offline-retry]")?.addEventListener("click", () => location.reload())
  addEventListener("online", () => location.reload())

  // The asked page, by its address.
  const asked = pages.find(p => p.path === location.pathname)
  if (asked) {
    const sentence = asked.kind === "page" ? strings.asked : strings.asked_area
    const [before, after = ""] = sentence.split("%{page}")
    const name = document.createElement("b")
    name.textContent = asked.name
    $("[data-offline-asked]").replaceChildren(before, name, after)
  }

  // Last connection, written by every page loaded online (ui/offline.js).
  try {
    const last = Number(localStorage.getItem("last-online"))
    if (last) {
      const time = $("[data-offline-last-time]")
      time.dateTime = new Date(last).toISOString()
      time.textContent = new Intl.DateTimeFormat(document.documentElement.lang, {dateStyle: "medium", timeStyle: "short"}).format(last)
      $("[data-offline-last]").hidden = false
    }
  } catch (_) {}

  // Pages saved on this device.
  if (!("caches" in window)) return
  const saved = new Set()
  for (const key of await caches.keys()) {
    if (!key.startsWith("pages-")) continue
    for (const req of await (await caches.open(key)).keys()) saved.add(new URL(req.url).pathname)
  }
  // Shown: the regions page and the ranking, then country pages.
  const here = pages.filter(p => saved.has(p.path) && p.path !== location.pathname)
  const shown = [...here.filter(p => p.kind === "page").slice(0, 2), ...here.filter(p => p.kind === "country")].slice(0, SHOWN)
  const list = $("[data-offline-list]")
  const template = list.querySelector("li")
  for (const page of shown) {
    const item = template.cloneNode(true)
    item.querySelector("a").href = page.path
    item.querySelector("a span").textContent = page.name
    list.append(item)
  }
  if (!saved.has(home)) template.remove()

  const countries = pages.filter(p => p.kind === "country")
  const savedCountries = countries.filter(p => saved.has(p.path)).length
  const rest = here.filter(p => p.kind === "country" && !shown.includes(p)).length
  if (rest > 0) {
    const more = $("[data-offline-more]")
    more.textContent = rest === 1 ? strings.more_one : strings.more.replace("%{count}", rest)
    more.hidden = false
  }
  $("[data-offline-count]").textContent = strings.count.replace("%{saved}", savedCountries).replace("%{total}", countries.length)
  const bar = $("[data-offline-bar]")
  bar.setAttribute("aria-valuenow", savedCountries)
  bar.firstElementChild.style.inlineSize = `${Math.round((savedCountries / countries.length) * 100)}%`
  $("[data-offline-progress]").hidden = false
  $("[data-offline-pending]").hidden = savedCountries === countries.length
}
