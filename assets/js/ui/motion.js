// Numbers that count up to their value (elements with data-count), once,
// when they come into view. The text is already right in the HTML: without
// JavaScript, or with reduced motion, nothing moves.

export const reducedMotion = () => matchMedia("(prefers-reduced-motion: reduce)").matches

const formatters = {}
// A signed percentage by default; {unit: "Md$", signed: false} for amounts.
function format(value, locale, {unit = "%", signed = true, decimals = 1} = {}) {
  const key = locale + decimals
  const f = (formatters[key] ||= new Intl.NumberFormat(locale, {minimumFractionDigits: decimals, maximumFractionDigits: decimals}))
  const sign = value < 0 ? "\u2212" : signed && value > 0 ? "+" : ""
  return sign + f.format(Math.abs(value)) + "\u00a0" + unit
}

// Animates el's text from `from` to `to`, then puts back the text the
// server or the caller wrote, so the last frame is always exact.
export function countUp(el, to, from = 0, options = {}, duration = 600) {
  const locale = document.documentElement.lang || "fr"
  if (to == null || isNaN(to) || reducedMotion()) return
  cancelAnimationFrame(el._countRaf)
  const finalText = el._countFinal && el._countRaf ? el._countFinal : el.textContent
  el._countFinal = finalText
  const decimals = options.decimals ?? (options.unit && Math.abs(to) >= 1000 ? 0 : 1)
  const t0 = performance.now()
  const step = t => {
    const k = Math.min(1, (t - t0) / duration)
    const eased = 1 - Math.pow(1 - k, 3)
    if (k < 1) {
      el.textContent = format(from + (to - from) * eased, locale, {...options, decimals})
      el._countRaf = requestAnimationFrame(step)
    } else {
      el.textContent = finalText
      el._countRaf = null
    }
  }
  el._countRaf = requestAnimationFrame(step)
}

export function initCountUp() {
  if (document.documentElement.classList.contains("revisit") || reducedMotion()) return
  const els = document.querySelectorAll("[data-count]")
  if (!els.length || !("IntersectionObserver" in window)) return
  const io = new IntersectionObserver(entries => {
    entries.forEach(entry => {
      if (!entry.isIntersecting) return
      io.unobserve(entry.target)
      countUp(entry.target, parseFloat(entry.target.dataset.count))
    })
  }, {threshold: 0.6})
  els.forEach(el => io.observe(el))
}

// Scroll reveal fallback where scroll-driven animations are missing
// (Firefox): blocks below the fold wait 32 px lower and rise as they
// arrive, once. Blocks already in view never move.
export function initScrollReveal() {
  if (CSS.supports("(animation-timeline: view()) and (animation-range: entry)")) return
  if (reducedMotion() || !("IntersectionObserver" in window)) return
  const blocks = [...document.querySelectorAll(".section > .wrap > *")]
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
