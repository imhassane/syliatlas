defmodule SyliAtlas.Locales do
  @moduledoc """
  The languages of the public site. French and English are the reference
  ones (their texts are written first); Spanish, Portuguese, Arabic, Hindi
  and Chinese are translations of them.

  - Paths and slugs: French, English, Spanish and Portuguese have their own
    (`/es/paises/senegal`); Arabic, Hindi and Chinese use the English ones
    under their prefix (`/ar/countries/senegal`): Latin addresses are easier
    to share and to read in a sitemap.
  - Arabic reads right to left.
  - The default language, for a reader whose language is not one of these,
    is English (`x-default`).
  """

  @all ~w(fr en es pt ar hi zh)

  @doc "Every language of the public site, in menu order."
  def all, do: @all

  @doc "The language for a reader we know nothing about."
  def default, do: "en"

  def valid?(locale), do: locale in @all

  @doc "The language whose path segments and slugs a language uses."
  def base(locale) when locale in ["fr", "en", "es", "pt"], do: locale
  def base(_locale), do: "en"

  def rtl?("ar"), do: true
  def rtl?(_), do: false

  def dir(locale), do: if(rtl?(locale), do: "rtl", else: "ltr")

  @doc "The language as hreflang and the html lang attribute want it."
  def tag("zh"), do: "zh-Hans"
  def tag(locale), do: locale

  @doc "Open Graph locale."
  def og("fr"), do: "fr_FR"
  def og("en"), do: "en_US"
  def og("es"), do: "es_ES"
  def og("pt"), do: "pt_PT"
  def og("ar"), do: "ar_AR"
  def og("hi"), do: "hi_IN"
  def og("zh"), do: "zh_CN"

  @doc "The language named in itself, for the language menu."
  def native("fr"), do: "Français"
  def native("en"), do: "English"
  def native("es"), do: "Español"
  def native("pt"), do: "Português"
  def native("ar"), do: "العربية"
  def native("hi"), do: "हिन्दी"
  def native("zh"), do: "中文"

  @doc "A value of a map keyed by language, falling back to English."
  def pick(nil, _locale), do: nil
  def pick(map, locale) when is_map(map), do: map[locale] || map["en"] || map["fr"]

  @doc "A map of every language to `fun.(locale)`."
  def each(fun), do: Map.new(@all, &{&1, fun.(&1)})

  # ---------------------------------------------------------------------------
  # The reader's language, for the bare address `/`.

  # Countries (ISO 3166-1 alpha-2, as Cloudflare's CF-IPCountry gives them)
  # and the language of the site their readers get.
  @french ~w(FR BE LU MC CH CA SN CI ML BF NE TG BJ GN CM GA CG CD CF TD MG DJ KM HT RE GP MQ GF YT NC PF PM BL MF WF SC MU RW BI DZ MA TN MR)
  @spanish ~w(ES MX AR CO PE VE CL EC GT CU BO DO HN PY SV NI CR PA UY PR GQ)
  @portuguese ~w(PT BR AO MZ CV GW ST TL MO)
  @arabic ~w(EG SD LY SA AE QA KW BH OM YE JO LB SY IQ PS SO EH)
  @hindi ~w(IN)
  @chinese ~w(CN TW HK SG)

  @doc "The language of the site for a country code, or nil."
  def for_country(nil), do: nil

  def for_country(code) do
    code = String.upcase(code)

    cond do
      code in @french -> "fr"
      code in @spanish -> "es"
      code in @portuguese -> "pt"
      code in @arabic -> "ar"
      code in @hindi -> "hi"
      code in @chinese -> "zh"
      true -> nil
    end
  end

  @doc """
  The first language of an Accept-Language header that the site has
  (« pt-BR,pt;q=0.9,en;q=0.8 » → « pt »), or nil.
  """
  def from_accept_language(nil), do: nil

  def from_accept_language(header) do
    header
    |> String.split(",")
    |> Enum.map(fn part ->
      [lang | params] = String.split(String.trim(part), ";")

      q =
        Enum.find_value(params, 1.0, fn p ->
          case String.split(String.trim(p), "=") do
            ["q", v] ->
              case Float.parse(v) do
                {f, _} -> f
                :error -> 0.0
              end

            _ ->
              nil
          end
        end)

      {lang |> String.downcase() |> String.split("-") |> hd(), q}
    end)
    |> Enum.filter(fn {lang, q} -> lang in @all and q > 0 end)
    |> Enum.sort_by(fn {_lang, q} -> -q end)
    |> case do
      [{lang, _} | _] -> lang
      [] -> nil
    end
  end
end
