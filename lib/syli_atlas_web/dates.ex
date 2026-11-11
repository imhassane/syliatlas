defmodule SyliAtlasWeb.Dates do
  @moduledoc """
  Dates in words in every language of the site: « 14 nov. 2025 »,
  “14 Nov 2025”, « 14 nov. 2025 » (es, pt), « 14 نوفمبر 2025 »,
  « 14 नवंबर 2025 », « 2025年11月14日 ».
  """

  @short %{
    "fr" => ~w(janv. févr. mars avr. mai juin juil. août sept. oct. nov. déc.),
    "en" => ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec),
    "es" => ~w(ene. feb. mar. abr. may. jun. jul. ago. sept. oct. nov. dic.),
    "pt" => ~w(jan. fev. mar. abr. mai. jun. jul. ago. set. out. nov. dez.)
  }

  @long %{
    "fr" =>
      ~w(janvier février mars avril mai juin juillet août septembre octobre novembre décembre),
    "en" =>
      ~w(January February March April May June July August September October November December),
    "es" =>
      ~w(enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre),
    "pt" =>
      ~w(janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro),
    "ar" => ~w(يناير فبراير مارس أبريل مايو يونيو يوليو أغسطس سبتمبر أكتوبر نوفمبر ديسمبر),
    "hi" => ~w(जनवरी फ़रवरी मार्च अप्रैल मई जून जुलाई अगस्त सितंबर अक्तूबर नवंबर दिसंबर)
  }

  @doc "The name of month `m` (1–12): `:short` or `:long`."
  def month(m, locale, style \\ :short)
  def month(m, "zh", _style), do: "#{m}月"

  def month(m, locale, :short) when is_map_key(@short, locale), do: Enum.at(@short[locale], m - 1)
  def month(m, locale, _style), do: Enum.at(@long[locale] || @long["en"], m - 1)

  @doc "Day, month and year."
  def day_month_year(d, m, y, locale, style \\ :short)
  def day_month_year(d, m, y, "zh", _style), do: "#{y}年#{m}月#{d}日"

  def day_month_year(d, m, y, "en", style) when style == :long,
    do: "#{month(m, "en", :long)} #{d}, #{y}"

  def day_month_year(d, m, y, "es", :long), do: "#{d} de #{month(m, "es", :long)} de #{y}"
  def day_month_year(d, m, y, "pt", :long), do: "#{d} de #{month(m, "pt", :long)} de #{y}"
  def day_month_year(d, m, y, locale, style), do: "#{d} #{month(m, locale, style)} #{y}"

  @doc "Day and month, without the year."
  def day_month(d, m, "zh"), do: "#{m}月#{d}日"
  def day_month(d, m, locale), do: "#{d} #{month(m, locale)}"

  @doc "Month and year: « oct. 2026 », “October 2026”, « 2026年10月 »."
  def month_year(m, y, locale, style \\ :short)
  def month_year(m, y, "zh", _style), do: "#{y}年#{m}月"

  def month_year(m, y, locale, :long) when locale in ["es", "pt"],
    do: "#{month(m, locale, :long)} de #{y}"

  def month_year(m, y, locale, style), do: "#{month(m, locale, style)} #{y}"
end
