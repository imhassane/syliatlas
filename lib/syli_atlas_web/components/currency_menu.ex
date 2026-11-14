defmodule SyliAtlasWeb.CurrencyMenu do
  @moduledoc """
  The header's currency menu (canvas « Sélecteur de devise »): « Show all
  amounts in », the currency of the reader's country first (« Auto »), the
  three references, then the African currencies, in a searchable list of
  ten rows that scrolls. Hidden until the script runs (`assets/js/ui/money.js`):
  without it, amounts stay as published. Carries the rates (see
  `SyliAtlasWeb.Money`).
  """
  use Phoenix.Component
  use Gettext, backend: SyliAtlasWeb.Gettext

  import SyliAtlasWeb.UI, only: [flag: 1]
  alias SyliAtlasWeb.Money

  attr :locale, :string, required: true
  attr :id, :string, default: "currency-menu"
  attr :class, :string, default: nil

  def currency_menu(assigns) do
    assigns =
      assign(assigns,
        rates: Money.client_rates(),
        options: Money.options(assigns.locale)
      )

    ~H"""
    <div
      :if={@rates}
      class={["cur-menu", @class]}
      id={@id}
      data-currency-menu
      data-your-country={
        gettext("Currency of your country: %{country} (detected)", country: "%{country}")
      }
      data-not-tracked={
        gettext("Your country: %{country} (detected) · currency not tracked, dollar by default",
          country: "%{country}"
        )
      }
      data-no-country={gettext("Country not detected: amounts as published")}
      data-no-rate={gettext("No exchange rate for that year: amount as published")}
      hidden
    >
      <button
        type="button"
        class="btn btn-quiet cur-btn"
        aria-haspopup="listbox"
        aria-expanded="false"
        aria-controls={@id <> "-pop"}
      >
        <span class="cur-mark" data-cur-mark aria-hidden="true"></span>
        <span class="sr-only">{gettext("Currency")} :</span>
        <span data-cur-label></span>
        <svg
          width="14"
          height="14"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          aria-hidden="true"
        ><path d="M6 9l6 6 6-6"></path></svg>
      </button>
      <div class="cur-pop" id={@id <> "-pop"} hidden>
        <p class="cur-pop-title">{gettext("Show all amounts in")}</p>
        <input
          type="search"
          class="cur-search"
          placeholder={gettext("Search: naira, KES, rand…")}
          aria-label={gettext("Search a currency")}
          aria-controls={@id <> "-list"}
          autocomplete="off"
        />
        <ul
          class="cur-list"
          role="listbox"
          id={@id <> "-list"}
          aria-label={gettext("Display currency")}
        >
          <li
            role="option"
            id={@id <> "-auto"}
            class="cur-auto"
            data-value="auto"
            data-search={gettext("auto country detected")}
            data-short=""
            aria-selected="true"
          >
            <span class="cur-mark"><span class="fx-sym">◎</span></span>
            <span class="cur-text">
              <span class="cur-auto-line">
                <b data-auto-name>{gettext("Currency of your country")}</b>
                <span class="cur-badge">Auto</span>
              </span>
              <span class="cur-sub" data-auto-sub>{gettext("Detecting your country…")}</span>
            </span>
          </li>
          <li class="cur-head" role="presentation">{gettext("Main")}</li>
          <li
            role="option"
            id={@id <> "-ORIG"}
            data-value="ORIG"
            data-name={gettext("Original currencies")}
            data-short={gettext("original")}
            data-search={gettext("original currencies as published")}
            aria-selected="false"
          >
            <span class="cur-mark"><span class="fx-sym">≡</span></span>
            <span class="cur-text"><b>{gettext("Original currencies")}</b></span>
            <span class="cur-code"></span>
          </li>
          <%= for {o, i} <- Enum.with_index(@options) do %>
            <li :if={i == 3} class="cur-head" role="presentation">{gettext("African currencies")}</li>
            <li
              role="option"
              id={"#{@id}-#{o.code}"}
              data-value={o.code}
              data-name={cap(o.name)}
              data-short={o.code}
              data-search={String.downcase(Enum.join([o.code, o.name | o.country_names], " "))}
              aria-selected="false"
            >
              <span class="cur-mark">
                <%= if o.countries == [] or o.code in ~w(XOF XAF) do %>
                  <span class="fx-sym">{Money.symbol(o.code)}</span>
                <% else %>
                  <.flag code={hd(o.countries)} size="sm" sprite />
                <% end %>
              </span>
              <span class="cur-text">
                <b>{cap(o.name)}</b>
                <span :if={o.country_names != []} class="cur-sub">
                  {Enum.join(Enum.take(o.country_names, 3), ", ")}{if length(o.country_names) > 3,
                    do: " …"}
                </span>
              </span>
              <span class="cur-code">{o.code}</span>
            </li>
          <% end %>
        </ul>
        <p class="cur-empty" hidden>{gettext("No currency found.")}</p>
        <p class="cur-note">
          {gettext(
            "Your choice is kept on this device and replaces the detection. Original amounts stay visible in small. Annual figures use the average rate of their year."
          )}
        </p>
      </div>
      <script type="application/json" data-money-rates>
        <%= Phoenix.HTML.raw(@rates) %>
      </script>
    </div>
    """
  end

  defp cap(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest
  defp cap(other), do: other
end
