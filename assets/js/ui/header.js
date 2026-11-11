// The header and its band (.site-top, sticky): hidden while reading down,
// back as soon as the reader scrolls up, with a shadow once the page has
// moved under them. Also the « back to top » button far down a page, and
// the pill that follows the pointer along the main menu.
import {reducedMotion} from "./motion"

export function initHeader() {
  const top = document.querySelector("[data-site-top]")
  if (!top) return
  const root = document.documentElement
  const toTop = document.querySelector("[data-to-top]")
  if (toTop) toTop.hidden = false

  let last = scrollY
  let ticking = false
  // Opened at an anchor further down: start with the header out of the way.
  if (location.hash && scrollY > top.offsetHeight) top.classList.add("is-hidden")

  const update = () => {
    ticking = false
    const y = Math.max(0, scrollY)
    const menuOpen = top.querySelector("details[open]")
    if (y > last + 4 && y > top.offsetHeight * 1.5 && !menuOpen) top.classList.add("is-hidden")
    else if (y < last - 4 || y <= top.offsetHeight) top.classList.remove("is-hidden")
    if (Math.abs(y - last) > 4) last = y
    top.classList.toggle("is-scrolled", y > 4)
    root.classList.toggle("is-far", y > innerHeight * 1.5)
  }

  addEventListener("scroll", () => {
    if (!ticking) { ticking = true; requestAnimationFrame(update) }
  }, {passive: true})
  update()

  toTop?.addEventListener("click", () => {
    scrollTo({top: 0, behavior: reducedMotion() ? "instant" : "smooth"})
    document.getElementById("main")?.focus?.({preventScroll: true})
  })

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
