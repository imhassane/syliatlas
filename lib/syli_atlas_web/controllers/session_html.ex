defmodule SyliAtlasWeb.SessionHTML do
  use SyliAtlasWeb, :html

  alias SyliAtlasWeb.Paths

  embed_templates "session_html/*"

  attr :id, :string, required: true
  attr :action, :string, required: true, doc: "sign-in | register | admin"
  attr :class, :string, default: "btn btn-primary"
  attr :name, :string, default: nil, doc: "name field of a registration"
  slot :inner_block, required: true

  @doc """
  A button running a passkey ceremony (`assets/js/ui/passkeys.js`); hidden
  until the script has checked the browser supports passkeys.
  """
  def passkey_button(assigns) do
    ~H"""
    <button
      type="button"
      id={@id}
      class={[@class, "passkey-btn"]}
      data-passkey={@action}
      data-passkey-name={@name}
      data-error={gettext("The passkey did not work. Try again, or use a code.")}
      hidden
    >
      <.fingerprint />
      {render_slot(@inner_block)}
    </button>
    """
  end

  def fingerprint(assigns) do
    ~H"""
    <svg
      width="20"
      height="20"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.8"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    ><path d="M12 11v3a8 8 0 0 1-1.5 4.7"></path><path d="M8.5 8.6A4 4 0 0 1 16 11v1.5"></path><path d="M5 10a7 7 0 0 1 13.4-2.8">
    </path><path d="M8 13.5a14 14 0 0 1-1 4.5"></path><path d="M16 15.5a17 17 0 0 1-.8 4"></path><path d="M19 11v.5">
    </path></svg>
    """
  end
end
