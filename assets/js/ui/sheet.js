// Bottom sheets (UI.filter_sheet/1): native popovers that open the filters
// on phones. Dragged down from their top (content not scrolled), they
// follow the finger, then close past 80 px or a flick; else they come back.
export function initSheets() {
  document.querySelectorAll(".sheet[popover]").forEach(sheet => {
    let start = null
    let offset = 0

    sheet.addEventListener("touchstart", event => {
      start = sheet.scrollTop <= 0 ? {y: event.touches[0].clientY, time: Date.now()} : null
      offset = 0
    }, {passive: true})

    sheet.addEventListener("touchmove", event => {
      if (!start) return
      offset = Math.max(0, event.touches[0].clientY - start.y)
      sheet.style.transition = "none"
      sheet.style.transform = offset > 0 ? `translateY(${offset}px)` : ""
    }, {passive: true})

    const end = () => {
      if (!start) return
      const speed = offset / Math.max(1, Date.now() - start.time)
      start = null
      sheet.style.transition = ""
      sheet.style.transform = ""
      if (offset > 80 || (offset > 24 && speed > 0.6)) sheet.hidePopover()
    }
    sheet.addEventListener("touchend", end)
    sheet.addEventListener("touchcancel", end)
  })
}
