// Period forms submit on change: no "Update" press needed with JavaScript.
// The button stays for keyboard users without JavaScript, and on phones,
// where the form sits in a bottom sheet and its button closes the choice.
export function initPeriodForms() {
  const inline = matchMedia("(min-width: 40rem)")

  document.querySelectorAll("form[data-period]").forEach(form => {
    form.addEventListener("change", event => {
      if (!event.target.matches("select")) return
      if (!form.closest(".sheet") || inline.matches) form.requestSubmit()
    })
  })
}
