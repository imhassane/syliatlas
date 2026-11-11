// Public pages are cached without a session: they show "Sign in" and a
// star that leads to sign-in. Here, one request to /account/me (private,
// never cached) tells who is signed in; the header link becomes "My space"
// and the stars become toggles, sent with the token /account/me gives.

export async function initAccount() {
  const links = document.querySelectorAll("a[data-space-href]")
  const stars = document.querySelectorAll("[data-favorite]")
  if (!links.length && !stars.length) return
  if (document.querySelector("meta[name='csrf-token']") && !stars.length) return

  let me
  try {
    const response = await fetch("/account/me", {credentials: "same-origin", headers: {accept: "application/json"}})
    if (!response.ok) return
    me = await response.json()
  } catch (_offline) {
    return
  }
  if (!me.signed_in) return

  links.forEach((a) => {
    a.href = me.account
    a.textContent = a.dataset.spaceLabel
  })

  let followed = new Set(me.favorites)
  stars.forEach((star) => {
    const render = () => {
      const on = followed.has(star.dataset.favorite)
      star.setAttribute("aria-pressed", String(on))
      star.querySelector("span").textContent = on ? star.dataset.labelOn : star.dataset.labelOff
    }
    render()
    star.setAttribute("role", "button")
    star.addEventListener("click", async (event) => {
      event.preventDefault()
      const [kind, ...rest] = star.dataset.favorite.split(":")
      const on = !followed.has(star.dataset.favorite)
      const response = await fetch("/account/favorites", {
        method: "POST",
        credentials: "same-origin",
        headers: {"content-type": "application/json", accept: "application/json", "x-csrf-token": me.csrf},
        body: JSON.stringify({kind, ref: rest.join(":"), on}),
      })
      if (response.ok) {
        followed = new Set((await response.json()).favorites)
        render()
      }
    })
  })
}
