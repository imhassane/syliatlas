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
end
