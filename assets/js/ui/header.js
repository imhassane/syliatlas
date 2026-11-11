// What stays at the top while reading: the band (sticky) and, under it, the
// filters of the page (tab bar of a profile, toolbar of a table). The header
// itself scrolls away. This measures them for the CSS (--sticky-top: the
// band's height; --filters-h: the filters', so anchors land below both),
// marks them once stuck (a shadow), and shows « back to top » far down a
// page. Also the pill that follows the pointer along the main menu.
import {reducedMotion} from "./motion"

export function initHeader() {
  const root = document.documentElement
  const band = document.getElementById("site-ticker")
  const filters = [...document.querySelectorAll("[data-sticky-filters]")]
  const toTop = document.querySelector("[data-to-top]")
  if (toTop) toTop.hidden = false

  const measure = () => {
    root.style.setProperty("--sticky-top", (band ? band.offsetHeight : 0) + "px")
    const shown = filters.find(f => f.offsetHeight > 0)
    root.style.setProperty("--filters-h", (shown ? shown.offsetHeight : 0) + "px")
  }
  measure()
  if ("ResizeObserver" in window) {
    const ro = new ResizeObserver(measure)
    if (band) ro.observe(band)
    filters.forEach(f => ro.observe(f))
  }

  let ticking = false
  const update = () => {
    ticking = false
    const top = band ? band.offsetHeight : 0
    if (band) band.classList.toggle("is-stuck", band.getBoundingClientRect().top <= 0 && scrollY > 0)
    filters.forEach(f => f.classList.toggle("is-stuck", f.getBoundingClientRect().top <= top + 0.5 && scrollY > 0))
    root.classList.toggle("is-far", scrollY > innerHeight * 1.5)
  }
  addEventListener("scroll", () => {
    if (!ticking) { ticking = true; requestAnimationFrame(update) }
  }, {passive: true})
  update()

  toTop?.addEventListener("click", () => scrollTo({top: 0, behavior: reducedMotion() ? "instant" : "smooth"}))

  initNavPill()
}

function initNavPill() {
  const nav = document.querySelector(".nav-desktop")
  if (!nav || reducedMotion() || !matchMedia("(hover: hover)").matches) return
  const pill = document.createElement("span")
  pill.className = "nav-pill"
  pill.setAttribute("aria-hidden", "true")
  nav.prepend(pill)

  const items = [...nav.querySelectorAll(":scope > a, :scope > .nav-menu > summary")]
  const place = el => {
    const n = nav.getBoundingClientRect(), r = el.getBoundingClientRect()
    pill.style.width = r.width + "px"
    pill.style.height = r.height + "px"
    pill.style.transform = `translate(${r.left - n.left}px, ${r.top - n.top}px)`
  }
  // The first hover starts from the current item, so the pill never flies in.
  const current = items.find(el => el.matches("[aria-current]")) || items[0]
  if (current) place(current)
  pill.getBoundingClientRect()

  items.forEach(el => el.addEventListener("pointerenter", () => {
    place(el)
    pill.classList.toggle("is-on", !el.matches("[aria-current]"))
  }))
  nav.addEventListener("pointerleave", () => {
    pill.classList.remove("is-on")
    if (current) place(current)
  })
}
