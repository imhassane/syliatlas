defmodule SyliAtlasWeb.IndicatorYearHTML do
  use SyliAtlasWeb, :html
  alias SyliAtlasWeb.{IndicatorYear, IndicatorYearController}

  embed_templates "indicator_year_html/*"

  def value_text(v, key, locale), do: IndicatorYearController.value_text(v, key, locale)
  def status_label(s), do: IndicatorYearController.status_label(s)
  def label(key), do: IndicatorYearController.label(key)
  def year_path(locale, area, key, year), do: IndicatorYear.path(locale, area, key, year)
end
