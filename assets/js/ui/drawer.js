// Navigation drawer for phones (see Layouts.nav_drawer/1), from the end
// (right) edge.
//
// The drawer is a popover="manual" holding a horizontal scroll-snap
// container with two stops: an empty spacer (closed, scroll start) and the
// sheet (open, scroll end).
// The browser drives the swipe (momentum, snapping); an IntersectionObserver
// on the sheet tells when it is fully open or fully gone, whatever moved it.
export function initDrawer() {
  const drawer = document.getElementById("nav-drawer")
  const openBtn = document.getElementById("drawer-open")
  if (!drawer || !openBtn || !("showPopover" in drawer)) return

  const scroller = drawer.querySelector(".drawer-scroller")
  const sheet = drawer.querySelector(".drawer-sheet")
  const main = () => document.querySelectorAll("main, .site-header, .site-footer")

  // Scroll start (0) is closed. The open stop is the far end; in
  // right-to-left, scrollLeft counts negative.
  const openLeft = () => (getComputedStyle(scroller).direction === "rtl" ? -1 : 1) * scroller.scrollWidth

  async function open() {
    drawer.showPopover()
    if (!CSS.supports("scroll-initial-target", "nearest")) {
      scroller.scrollTo({left: 0, behavior: "instant"})
      await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))
    }
    scroller.scrollTo({left: openLeft(), behavior: "auto"})
  }

  function close() {
    if (!drawer.matches(":popover-open")) return
    // Do not hide the popover here: the observer does it once the sheet has
    // left the screen, so the slide-out stays visible.
    scroller.scrollTo({left: 0, behavior: "auto"})
  }

  function opened() {
    main().forEach(el => (el.inert = true))
    openBtn.setAttribute("aria-expanded", "true")
    sheet.focus({preventScroll: true})
  }

  function closed() {
    if (drawer.matches(":popover-open")) drawer.hidePopover()
    main().forEach(el => (el.inert = false))
    openBtn.setAttribute("aria-expanded", "false")
    if (drawer.contains(document.activeElement) || document.activeElement === document.body) openBtn.focus()
  }

  const visible = 1 / window.innerWidth
  new IntersectionObserver(
    entries => {
      const entry = entries.at(-1)
      if (!drawer.matches(":popover-open")) return
      if (entry.intersectionRatio < visible) closed()
      if (entry.intersectionRatio === 1) opened()
    },
    {root: drawer, threshold: [visible, 1]}
  ).observe(sheet)

  // Backdrop fade without scroll-driven animations (Firefox).
  if (!CSS.supports("animation-timeline: scroll()")) {
    scroller.addEventListener("scroll", () => {
      const ratio = Math.abs(scroller.scrollLeft) / sheet.offsetWidth
      drawer.style.setProperty("--drawer-backdrop", Math.max(0, Math.min(1, ratio)))
    }, {passive: true})
  }

  openBtn.addEventListener("click", open)
  drawer.addEventListener("click", event => {
    if (!sheet.contains(event.target) || event.target.closest("[data-drawer-close]")) close()
  })
  document.addEventListener("keydown", event => {
    if (event.key === "Escape") close()
  })
  // The drawer is for phones: close it if the window grows past them.
  matchMedia("(min-width: 60rem)").addEventListener("change", e => e.matches && closed())
}
