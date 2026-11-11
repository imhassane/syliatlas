// Page transitions, old page side. The new page side runs in the root layout
// (it must act before the first paint), which defines window.SyliVT; the
// look is in motion.css. Before the browser takes its snapshot, this names
// the kind of move and marks the elements that travel (tab bar, underline,
// tab content, table rows), and remembers where the tab bar or the table
// sat on screen so the new page puts it at the same place.
export function initTransitions() {
  addEventListener("pageswap", e => {
    const VT = window.SyliVT
    const to = e.activation?.entry?.url
    if (!VT || !to) return
    const url = new URL(to)
    if (url.origin !== location.origin) return
    const kind = VT.kind(location.pathname, url.pathname, document)
    if (!kind) return
    VT.save(kind, document, url.href)
    if (e.viewTransition) {
      e.viewTransition.types.add(kind)
      VT.mark(kind, document)
    }
  })
  // Back from the cache: the marks of the last move must not stay.
  addEventListener("pageshow", e => { if (e.persisted) window.SyliVT?.clear(document) })

  centerCurrentTab()
}

// On a phone the tab bar scrolls: show the current tab in its middle.
function centerCurrentTab() {
  const nav = document.getElementById("profile-tabs")
  const tab = nav?.querySelector("[aria-current='page']")
  if (!tab || nav.scrollWidth <= nav.clientWidth) return
  nav.scrollLeft = tab.offsetLeft - (nav.clientWidth - tab.offsetWidth) / 2
}
