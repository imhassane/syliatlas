defmodule SyliAtlas.Budgets.Money do
  @moduledoc """
  Budget amounts written short, as the pages and emails show them:
  « 6,09 Md € », « 233 M € », « 67 926 Md GNF », « 4,4 bn $ ».
  The same rule runs in the browser (`assets/js/ui/money.js`) when the reader
  chooses another currency.
  """

  @symbols %{"EUR" => "€", "USD" => "$"}

  @doc "Short form of an amount (number or Decimal) in a currency."
  def short(nil, _currency, _locale), do: "—"
  def short(%Decimal{} = d, currency, locale), do: short(Decimal.to_float(d), currency, locale)

  def short(amount, currency, locale) when is_number(amount) do
    {value, unit} =
      cond do
        abs(amount) >= 1.0e9 -> {amount / 1.0e9, billion(locale)}
        abs(amount) >= 1.0e6 -> {amount / 1.0e6, million(locale)}
        true -> {amount * 1.0, nil}
      end

    decimals =
      cond do
        abs(value) >= 100 -> 0
        abs(value) >= 10 -> 1
        true -> 2
      end

    number = SyliAtlasWeb.Format.number(value, decimals, locale)
    symbol = Map.get(@symbols, currency, currency)
    Enum.join(Enum.reject([number, unit, symbol], &is_nil/1), " ")
  end

  @doc "The amount converted between two currencies at the rates document (float), or nil."
  def convert(nil, _from, _to, _fx), do: nil
  def convert(%Decimal{} = d, from, to, fx), do: convert(Decimal.to_float(d), from, to, fx)
  def convert(amount, same, same, _fx) when is_number(amount), do: amount * 1.0

  def convert(amount, from, to, fx) when is_number(amount),
    do: SyliAtlas.Fx.convert(fx, amount, from, to)

  @doc "The currency amounts are shown in by default, before the reader chooses."
  def default_currency("fr"), do: "EUR"
  def default_currency(_), do: "USD"

  defp billion("fr"), do: "Md"
  defp billion(locale), do: SyliAtlasWeb.Format.billion_word(locale)
  defp million("fr"), do: "M"
  defp million("es"), do: "M"
  defp million("pt"), do: "M"
  defp million("ar"), do: "مليون"
  defp million("hi"), do: "मिलियन"
  defp million("zh"), do: "百万"
  defp million(_), do: "m"
end
