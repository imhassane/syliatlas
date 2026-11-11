defmodule SyliAtlasWeb.ApiDocI18n do
  @moduledoc """
  The API documentation page beyond French and English: its texts are
  written in French and English (SyliAtlasWeb.ApiDocHTML.tr/3, the OpenAPI
  description, the indicator catalogue); `priv/data/api_doc_i18n.json`
  gives, for each English text, its Spanish, Portuguese, Arabic, Hindi and
  Chinese version. A text without one stays in English.
  """

  @external_resource "priv/data/api_doc_i18n.json"
  @texts "priv/data/api_doc_i18n.json" |> File.read!() |> Jason.decode!()

  @doc "The English text `en` in `locale` (es, pt, ar, hi, zh), or `en` itself."
  def translate(en, locale) when is_binary(en), do: get_in(@texts, [en, locale]) || en
  def translate(en, _locale), do: en
end
