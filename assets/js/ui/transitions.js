// Page arrival, old page side: when a tab of a country profile or a filter
// or sort link of a table is clicked, write where things sit on screen so
// the new page can start from there (root layout, « page arrival »): the tab
// bar and its underline, or the table and each of its rows. No browser view
// transition: it would freeze the scrolling band in a still image.
const KEY = "arrival"

export function initTransitions() {
  document.addEventListener("click", e => {
    if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return
    const a = e.target.closest("a[href]")
    if (!a || a.origin !== location.origin || a.target) return

    const tabs = a.closest("#profile-tabs")
    if (tabs) {
      const links = [...tabs.querySelectorAll("a")]
      const from = links.findIndex(l => l.matches("[aria-current]"))
      const to = links.indexOf(a)
      if (from === to) return
      const bar = tabs.closest(".tab-bar") || tabs
      const ind = tabs.querySelector(".tab-indicator")?.getBoundingClientRect()
      return save({
        kind: "tab",
        to: a.href,
        top: bar.getBoundingClientRect().top,
        dir: to > from ? 1 : -1,
        ind: ind && {left: ind.left, width: ind.width}
      })
    }

    const box = a.closest("[data-keep-place]")
    if (box && a.pathname === location.pathname) {
      const top = box.getBoundingClientRect().top
      const rows = {}
      box.querySelectorAll("[data-reorder] > [id]").forEach(r => { rows[r.id] = r.getBoundingClientRect().top - top })
      save({kind: "reorder", to: a.href, top, rows})
    }
  }, true)

  centerCurrentTab()
}

function save(state) {
  try { sessionStorage.setItem(KEY, JSON.stringify(state)) } catch (_) {}
}

// On a phone the tab bar scrolls: show the current tab in its middle.
function centerCurrentTab() {
  const nav = document.getElementById("profile-tabs")
  const tab = nav?.querySelector("[aria-current='page']")
  if (!tab || nav.scrollWidth <= nav.clientWidth) return
  nav.scrollLeft = tab.offsetLeft - (nav.clientWidth - tab.offsetWidth) / 2
}
