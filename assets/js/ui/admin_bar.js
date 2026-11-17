// Public pages, for an administrator (canvas « Syli Atlas — publication sur
// X et LinkedIn », artboard C): a small bar at the bottom with where the
// page's latest post stands and « Partager sur les réseaux », which opens the
// post of this page in /admin/reseaux. Public pages are cached without a
// session, so the bar is drawn here, after /account/me said who is there.

const HIDDEN_KEY = "syli-admin-bar-hidden"

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

  bar.append(state, share, hide)
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
