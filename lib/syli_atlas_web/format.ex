defmodule SyliAtlasWeb.Format do
  @moduledoc """
  Number formatting in the languages of the site. Digits stay Western in
  every language (as in the Arabic, Hindi and Chinese financial press);
  separators follow the language: 1 234,5 (fr, pt), 1.234,5 (es),
  1,234.5 (en, ar, hi, zh).
  """
  alias SyliAtlas.Sources.Indicators

  @nbsp " "
  @thin " "

  @doc """
  Gettext bindings for a template naming a country or region: `%{name}` and,
  for French grammar, `%{of_name}` (du Sénégal), `%{in_name}` (au Sénégal),
  `%{the_name}`/`%{The_name}` (le Sénégal) and `%{e}` (noté, notée). See
  `SyliAtlas.Geo.French`. Uses the current Gettext locale.
  """
  def names(name, extra \\ []) do
    SyliAtlas.Geo.French.bindings(name, Gettext.get_locale(SyliAtlasWeb.Gettext)) ++ extra
  end

  @doc "Formats a number with the locale's separators."
  def number(nil, _decimals, _locale), do: "n.d."

  def number(value, decimals, locale) do
    rounded = :erlang.float_to_binary(value * 1.0, decimals: decimals)
    [int, frac] = String.split(rounded <> if(decimals == 0, do: ".", else: ""), ".", parts: 2)

    {sign, int} =
      if String.starts_with?(int, "-"), do: {"−", String.trim_leading(int, "-")}, else: {"", int}

    grouped =
      int
      |> String.reverse()
      |> String.graphemes()
      |> Enum.chunk_every(3)
      |> Enum.map_join(group_sep(locale), &Enum.join/1)
      |> String.reverse()

    decimal_sep = decimal_sep(locale)
    sign <> grouped <> if(frac == "", do: "", else: decimal_sep <> frac)
  end

  @doc "A signed change: percent for levels, points for rates."
  def change(nil, _indicator, locale), do: na(locale)

  def change(value, indicator, locale) do
    unit = if Indicators.get(indicator).kind == :rate, do: "pt", else: "%"
    sign = if value > 0, do: "+", else: ""
    sign <> number(value, 1, locale) <> @nbsp <> unit
  end

  @doc "An indicator value with its unit."
  def value(nil, _indicator, locale), do: na(locale)

  def value(v, indicator, locale) do
    case indicator do
      "real_gdp_growth" ->
        signed(v, locale) <> @nbsp <> "%"

      "inflation" ->
        number(v, 1, locale) <> @nbsp <> "%"

      "public_debt_pct_gdp" ->
        number(v, 1, locale) <> @nbsp <> "%"

      k when k in ["fiscal_balance_pct_gdp", "current_account_pct_gdp"] ->
        signed(v, locale) <> @nbsp <> "%"

      "unemployment" ->
        number(v, 1, locale) <> @nbsp <> "%"

      "gdp_usd_bn" ->
        number(v, if(v >= 1000, do: 0, else: 1), locale) <> @nbsp <> billions(locale)

      "gdp_per_capita_usd" ->
        number(v, 0, locale) <> @nbsp <> "$"

      "gdp_per_capita_ppp" ->
        number(v, 0, locale) <> @nbsp <> "$"

      "population_m" ->
        number(v, 1, locale) <> @nbsp <> "M"

      "real_gdp_index" ->
        number(v, 1, locale)
    end
  end

  def tone(nil, _indicator), do: nil

  def tone(value, indicator) do
    case Indicators.get(indicator).good do
      :up when value > 0 -> "up"
      :up when value < 0 -> "down"
      :down when value < 0 -> "up"
      :down when value > 0 -> "down"
      _ -> nil
    end
  end

  defp signed(v, locale), do: if(v > 0, do: "+", else: "") <> number(v, 1, locale)
  defp group_sep(locale) when locale in ["fr", "pt"], do: @thin
  defp group_sep("es"), do: "."
  defp group_sep(_), do: ","

  @doc "The decimal separator of a language."
  def decimal_sep(locale) when locale in ["fr", "pt", "es"], do: ","
  def decimal_sep(_), do: "."

  @doc "The short word for a billion: Md (fr), bn (en), mil M (es)…"
  def billion_word("fr"), do: "Md"
  def billion_word("es"), do: "mil M"
  def billion_word("pt"), do: "mil M"
  def billion_word("ar"), do: "مليار"
  def billion_word("hi"), do: "अरब"
  def billion_word("zh"), do: "十亿"
  def billion_word(_), do: "bn"

  def billions("fr"), do: "Md$"
  def billions("en"), do: "bn$"
  def billions(locale), do: billion_word(locale) <> " $"

  defp na("fr"), do: "n.d."
  defp na("es"), do: "n.d."
  defp na("pt"), do: "n.d."
  defp na(_), do: "n/a"
end
