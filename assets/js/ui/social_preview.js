// Admin « Réseaux »: the X and LinkedIn previews follow the text being typed.
// Each textarea[data-social-text] names its preview (data-preview); the
// preview's [data-preview-text] gets the text, X's counter its length (a link
// counts 23 characters, plus the line break before it: data-link-length).
// On LinkedIn, the text folds after three lines with « … voir plus », as on
// the network.
const X_LIMIT = 280

export function initSocialPreviews() {
  document.querySelectorAll("textarea[data-social-text]").forEach(field => {
    const preview = document.getElementById(field.dataset.preview)
    if (!preview) return
    const target = preview.querySelector("[data-preview-text]")
    const counter = document.querySelector(`[data-x-count="${field.id}"]`)
    const linkLength = Number(field.dataset.linkLength || 0)
    const text = preview.querySelector("[data-clamp]")
    const more = preview.querySelector("[data-more]")

    const fold = () => {
      if (!text || !more || preview.dataset.open === "true") return
      text.classList.add("is-clamped")
      more.hidden = text.scrollHeight <= text.clientHeight + 1
    }

    const update = () => {
      target.textContent = field.value
      if (counter) {
        const length = [...field.value].length + linkLength
        counter.textContent = `${length} / ${X_LIMIT}`
        counter.classList.toggle("adm-bad", length > X_LIMIT)
        counter.classList.toggle("subtle", length <= X_LIMIT)
      }
      fold()
    }

    more?.addEventListener("click", () => {
      preview.dataset.open = "true"
      text.classList.remove("is-clamped")
      more.hidden = true
    })

    field.addEventListener("input", update)
    fold()
  })
}
