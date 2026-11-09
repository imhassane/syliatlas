defmodule SyliAtlasWeb.Format do
  @moduledoc "Number formatting for French and English pages."
  alias SyliAtlas.Sources.Indicators

  @nbsp " "
  @thin " "

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
      |> Enum.map_join(if(locale == "en", do: ",", else: @thin), &Enum.join/1)
      |> String.reverse()

    decimal_sep = if locale == "en", do: ".", else: ","
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
  defp billions("en"), do: "bn$"
  defp billions(_), do: "Md$"
  defp na("en"), do: "n/a"
  defp na(_), do: "n.d."
end
