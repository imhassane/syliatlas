defmodule SyliAtlasWeb.MapScale do
  @moduledoc """
  How the home map colours countries: one indicator at a time, values cut
  into six classes. Classes are CSS classes (`q-seq-3`, `q-bad-2`, `q-none`)
  whose colours are tokens, so the map follows the theme. Sequential indigo
  where more is better or neutral, orange where more is worse.
  """
  use Gettext, backend: SyliAtlasWeb.Gettext
  alias SyliAtlasWeb.Format

  @indicators [
    %{key: "gdp", palette: "seq", bins: [5, 15, 40, 100, 250], unit: "bn"},
    %{key: "gdppc", palette: "seq", bins: [1000, 2000, 4000, 8000, 12000], unit: "$"},
    %{key: "inflation", palette: "bad", bins: [2, 5, 10, 20, 40], unit: "%"},
    %{key: "debt", palette: "bad", bins: [30, 50, 70, 90, 110], unit: "%"}
  ]

  def keys, do: Enum.map(@indicators, & &1.key)
  def valid?(key), do: key in keys()
  defp get(key), do: Enum.find(@indicators, &(&1.key == key))

  def label("gdp"), do: gettext("GDP")
  def label("gdppc"), do: gettext("GDP per capita")
  def label("inflation"), do: gettext("Inflation")
  def label("debt"), do: gettext("Public debt")

  def title("gdp", _from, to), do: gettext("GDP in current dollars %{year}", year: to)
  def title("gdppc", _from, to), do: gettext("GDP per capita %{year}", year: to)
  def title("inflation", _from, to), do: gettext("Inflation %{year}", year: to)
  def title("debt", _from, to), do: gettext("Public debt %{year}", year: to)

  @doc "CSS class of a value for an indicator."
  def class(_key, nil), do: "q-none"

  def class(key, v) do
    %{palette: p, bins: bins} = get(key)
    "q-#{p}-#{Enum.count(bins, &(v >= &1))}"
  end

  @doc "Legend entries: [{class, label}], lowest class first."
  def legend(key, locale) do
    %{palette: p, bins: bins, unit: unit} = get(key)
    n = fn v -> Format.number(v * 1.0, 0, locale) <> unit_suffix(unit, locale) end

    ranges =
      [gettext("below %{v}", v: n.(hd(bins)))] ++
        (bins
         |> Enum.chunk_every(2, 1, :discard)
         |> Enum.map(fn [a, b] -> gettext("%{a} to %{b}", a: n.(a), b: n.(b)) end)) ++
        [gettext("above %{v}", v: n.(List.last(bins)))]

    Enum.zip(Enum.map(0..5, &"q-#{p}-#{&1}"), ranges)
  end

  defp unit_suffix("%", _locale), do: " %"
  defp unit_suffix("bn", locale), do: " " <> Format.billions(locale)
  defp unit_suffix(u, _locale), do: " " <> u

  @doc "A country's value for an indicator, formatted."
  def value_text("gdp", c, locale), do: Format.value(c["gdp"], "gdp_usd_bn", locale)
  def value_text("gdppc", c, locale), do: Format.value(c["gdppc"], "gdp_per_capita_usd", locale)
  def value_text("inflation", c, locale), do: Format.value(c["inflation"], "inflation", locale)
  def value_text("debt", c, locale), do: Format.value(c["debt"], "public_debt_pct_gdp", locale)
end
