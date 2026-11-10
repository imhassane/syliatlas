// Syli Atlas: the script of every page. It holds the site's own behaviour
// (map, drawer, filter sheets, toasts, updates, install, motion) and nothing
// heavy: the LiveView client lives in live.js, loaded only by LiveView pages
// (see SyliAtlasWeb.LiveAssets), so public pages never download it.

import "../css/app.css"
// phoenix_html handles links and buttons with data-method (sign-out, deletes).
import "phoenix_html"

import {initDrawer} from "./ui/drawer"
import {initSheets} from "./ui/sheet"
import {initTheme} from "./ui/theme"
import {initPeriodForms} from "./ui/period"
import {initMap} from "./ui/map"
import {initUpdates} from "./ui/updates"
import {initInstall} from "./ui/install"
import {initCountUp, initScrollReveal} from "./ui/motion"
import {initMarketSearch} from "./ui/market"

initTheme()
initDrawer()
initSheets()
initPeriodForms()
initMap()
initUpdates()
initInstall()
initCountUp()
initScrollReveal()
initMarketSearch()

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

