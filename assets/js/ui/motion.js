// Motion helpers. Figures never animate: no counting, no rolling digits
// (the text is the value). Nothing moves with reduced motion.

export const reducedMotion = () => matchMedia("(prefers-reduced-motion: reduce)").matches

const GRIDS = ".grid, .overview-grid, .related-grid"

// Scroll reveal fallback where scroll-driven animations are missing
// (Firefox): blocks below the fold wait 32 px lower and rise as they
// arrive, once. Blocks already in view never move. As in motion.css, a
// block holding a grid does not move as one: its cards rise one by one.
export function initScrollReveal() {
  if (CSS.supports("(animation-timeline: view()) and (animation-range: entry)")) return
  if (reducedMotion() || !("IntersectionObserver" in window)) return
  const blocks = [...document.querySelectorAll(".section > .wrap > *")].flatMap(el => {
    if (el.matches(GRIDS)) return [...el.children]
    if (!el.querySelector(GRIDS)) return [el]
    return [...el.children].flatMap(c => (c.matches(GRIDS) ? [...c.children] : [c]))
  })
  const below = blocks.filter(el => el.getBoundingClientRect().top > innerHeight)
  if (!below.length) return
  const io = new IntersectionObserver(entries => {
    entries.forEach(entry => {
      if (!entry.isIntersecting) return
      io.unobserve(entry.target)
      entry.target.classList.add("reveal-arrive")
      entry.target.classList.remove("reveal-pending")
    })
  }, {rootMargin: "0px 0px -8% 0px"})
  below.forEach(el => { el.classList.add("reveal-pending"); io.observe(el) })
}
