defmodule SyliAtlasWeb.CurrencyHTML do
  use SyliAtlasWeb, :html
  alias SyliAtlasWeb.{CurrencyController, Pagination}

  embed_templates "currency_html/*"

  def regime_tab(nil), do: gettext("All")
  def regime_tab("floating"), do: gettext("Floating or managed")
  def regime_tab("EUR"), do: gettext("Pegged to the euro")
  def regime_tab("ZAR"), do: gettext("Pegged to the rand")
  def regime_tab("USD"), do: gettext("Pegged to the dollar")

  def regime_label("floating"), do: gettext("floating or managed")
  def regime_label("EUR"), do: gettext("pegged to the euro")
  def regime_label("ZAR"), do: gettext("at par with the rand")
  def regime_label("USD"), do: gettext("pegged to the dollar")

  def base_tab("USD"), do: gettext("Dollar")
  def base_tab("EUR"), do: gettext("Euro")
  def base_tab("CNY"), do: gettext("Yuan")

  def symbol("USD"), do: "$"
  def symbol("EUR"), do: "€"
  def symbol("CNY"), do: "¥"
  def symbol(code), do: code

  @doc "Link to the list with one parameter changed (the others kept, defaults dropped)."
  def list_href(locale, kept, key, value) do
    params =
      kept
      |> Map.put(key, value)
      |> Enum.reject(fn {k, v} -> {k, v} in [{"base", "USD"}, {"sort", "change"}] end)
      |> Map.new()

    Pagination.href(Paths.currencies(locale), params, "page", 1)
  end

  @doc "A rate with the precision its size needs."
  def rate(nil, _locale), do: "—"
  def rate(v, locale) when v >= 1000, do: number(v, 0, locale)
  def rate(v, locale) when v >= 10, do: number(v, 2, locale)
  def rate(v, locale) when v >= 0.01, do: number(v, 4, locale)
  def rate(v, locale), do: number(v, 6, locale)

  def tone(nil), do: "muted"
  def tone(c) when c > 0.05, do: "up"
  def tone(c) when c < -0.05, do: "down"
  def tone(_), do: "muted"

  def arrow(nil), do: ""
  def arrow(c) when c > 0.05, do: "▲ "
  def arrow(c) when c < -0.05, do: "▼ "
  def arrow(_), do: "■ "

  defdelegate signed(c, locale), to: CurrencyController
  defdelegate date_text(iso, locale), to: CurrencyController
  defdelegate base_name(base), to: CurrencyController

  @doc "First letter in capitals (currency names are written in lower case in French)."
  def cap(""), do: ""

  def cap(text) do
    {first, rest} = String.split_at(text, 1)
    String.upcase(first) <> rest
  end

  def countries_text(row) do
    case row.country_names do
      [one] -> one
      many -> ngettext("1 country", "%{count} countries", length(many))
    end
  end

  def choice_label(code, locale) do
    name =
      case code do
        "USD" -> gettext("US dollar")
        "EUR" -> gettext("euro")
        "CNY" -> gettext("Chinese yuan")
        c -> SyliAtlas.Economy.Currencies.name_of(c, locale) || c
      end

    code <> " · " <> name
  end

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :options, :list, required: true, doc: "%{code, name, countries, country_names}"
  attr :selected, :string, required: true
  attr :locale, :string, required: true

  @doc """
  A currency choice. Without JavaScript, a plain select. With it
  (`assets/js/ui/currency_picker.js`), a button opening a searchable list
  of ten rows that scrolls, like the long tables: flags, name, code and
  countries, searched by any of them. The select keeps the value sent.
  """
  def currency_picker(assigns) do
    current = Enum.find(assigns.options, &(&1.code == assigns.selected))
    assigns = assign(assigns, :current, current)

    ~H"""
    <div class="field fx-pick" data-currency-picker id={@id <> "-field"}>
      <label for={@id}>{@label}</label>
      <select id={@id} name={@name} class="fx-pick-native">
        <option :for={o <- @options} value={o.code} selected={o.code == @selected}>
          {o.code} · {cap(o.name)}
        </option>
      </select>
      <div class="fx-pick-ui" hidden>
        <button
          type="button"
          class="fx-pick-btn"
          aria-haspopup="listbox"
          aria-expanded="false"
          aria-controls={@id <> "-pop"}
          aria-label={@label}
        >
          <span class="fx-pick-current" data-current>
            <.currency_mark :if={@current} option={@current} />
            <b>{@current && @current.code}</b>
            <span class="fx-pick-name">{@current && cap(@current.name)}</span>
          </span>
          <span class="fx-pick-chev" aria-hidden="true">▾</span>
        </button>
        <div class="fx-pick-pop" id={@id <> "-pop"} hidden>
          <input
            type="search"
            class="fx-pick-search"
            placeholder={gettext("Currency, code or country")}
            aria-label={gettext("Search a currency")}
            autocomplete="off"
            aria-controls={@id <> "-list"}
          />
          <ul class="fx-pick-list" role="listbox" id={@id <> "-list"} aria-label={@label}>
            <li
              :for={o <- @options}
              role="option"
              id={"#{@id}-#{o.code}"}
              data-value={o.code}
              data-search={String.downcase(Enum.join([o.code, o.name | o.country_names], " "))}
              aria-selected={to_string(o.code == @selected)}
            >
              <.currency_mark option={o} />
              <span class="fx-pick-text">
                <b>{cap(o.name)}</b>
                <span :if={o.country_names != []} class="small muted">
                  {Enum.join(Enum.take(o.country_names, 3), ", ")}{if length(o.country_names) > 3,
                    do: " …"}
                </span>
              </span>
              <span class="fx-pick-code">{o.code}</span>
            </li>
          </ul>
          <p class="fx-pick-empty small muted" hidden>{gettext("No currency found.")}</p>
        </div>
      </div>
    </div>
    """
  end

  attr :option, :map, required: true

  defp currency_mark(assigns) do
    ~H"""
    <span class="fx-flags" aria-hidden="true">
      <%= if @option.countries == [] do %>
        <span class="fx-sym">{symbol(@option.code)}</span>
      <% else %>
        <.flag :for={c <- Enum.take(@option.countries, 2)} code={c} size="sm" sprite />
      <% end %>
    </span>
    """
  end
end
