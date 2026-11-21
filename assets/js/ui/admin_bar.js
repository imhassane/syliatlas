// Public pages, for an administrator (canvas « Syli Atlas — publication sur
// X et LinkedIn », artboard C): a small bar at the bottom with where the
// page's latest post stands and « Partager sur les réseaux », which opens the
// post of this page in /admin/reseaux. Public pages are cached without a
// session, so the bar is drawn here, after /account/me said who is there.
//
// « Copier le lien » X / LinkedIn / WhatsApp: copies the page's address with
// UTM tags, so Plausible sorts the visits by network (LinkedIn's app and
// WhatsApp send no referrer: without the tags they land in « Direct »).

const HIDDEN_KEY = "syli-admin-bar-hidden"
const NETWORKS = [
  {source: "x", label: "X"},
  {source: "linkedin", label: "LinkedIn"},
  {source: "whatsapp", label: "WhatsApp"},
]

// The canonical address (production host, no session-only parameters) when
// the page declares one; the current address otherwise. Existing parameters
// (a ranking's filters) are kept; old UTM tags are replaced.
export function taggedUrl(source, doc = document, loc = location) {
  const canonical = doc.querySelector('link[rel="canonical"]')?.href
  const url = new URL(canonical || loc.href)
  if (!canonical) url.hash = ""
  url.searchParams.set("utm_source", source)
  url.searchParams.set("utm_medium", "social")
  url.searchParams.set("utm_campaign", "partage")
  return url.toString()
}

function copyGroup() {
  const group = document.createElement("span")
  group.className = "admin-bar-copy"
  group.setAttribute("role", "group")
  group.setAttribute("aria-label", "Copier le lien de la page avec le suivi")

  const title = document.createElement("span")
  title.textContent = "Copier le lien"
  title.setAttribute("aria-hidden", "true")

  const status = document.createElement("span")
  status.className = "admin-bar-status"
  status.setAttribute("role", "status")

  group.append(title)
  for (const {source, label} of NETWORKS) {
    const button = document.createElement("button")
    button.type = "button"
    button.id = `admin-bar-copy-${source}`
    button.textContent = label
    button.setAttribute("aria-label", `Copier le lien pour ${label}`)
    let timer = null
    button.addEventListener("click", async () => {
      const link = taggedUrl(source)
      let message
      try {
        await navigator.clipboard.writeText(link)
        message = `Lien ${label} copié`
        button.textContent = "✓ Copié"
      } catch (_denied) {
        message = `Copie impossible : ${link}`
        button.textContent = "Échec"
      }
      status.textContent = ""
      requestAnimationFrame(() => { status.textContent = message })
      clearTimeout(timer)
      timer = setTimeout(() => {
        button.textContent = label
        status.textContent = ""
      }, 2000)
    })
    group.append(button)
  }
  group.append(status)
  return group
}

export async function showAdminBar() {
  if (document.getElementById("admin-bar")) return
  const path = location.pathname.replace(/\/$/, "")
  if (!/^\/[a-z]{2}(\/|$)/.test(path)) return
  try {
    if (sessionStorage.getItem(HIDDEN_KEY) === "1") return
  } catch (_blocked) {}

  const bar = document.createElement("div")
  bar.id = "admin-bar"
  bar.className = "admin-bar"
  bar.setAttribute("role", "region")
  bar.setAttribute("aria-label", "Administration")

  const state = document.createElement("span")
  state.textContent = "Admin"

  const share = document.createElement("a")
  share.href = `/admin/reseaux/partager?page=${encodeURIComponent(path)}`
  share.textContent = "Partager sur les réseaux"

  const hide = document.createElement("button")
  hide.type = "button"
  hide.textContent = "×"
  hide.setAttribute("aria-label", "Masquer la barre d'administration")
  hide.addEventListener("click", () => {
    bar.remove()
    try {
      sessionStorage.setItem(HIDDEN_KEY, "1")
    } catch (_blocked) {}
  })

  bar.append(state, share, copyGroup(), hide)
  document.body.append(bar)

  try {
    const response = await fetch(`/admin/reseaux/page?chemin=${encodeURIComponent(path)}`, {
      credentials: "same-origin",
      headers: {accept: "application/json"},
    })
    if (!response.ok) return
    const page = await response.json()
    state.textContent = `Admin · page ${page.state}`
  } catch (_offline) {}
}
