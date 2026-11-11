defmodule SyliAtlasWeb.Paths do
  @moduledoc "Localised, readable URLs: /fr/pays/cote-d-ivoire, /en/countries/cote-d-ivoire."

  alias SyliAtlas.Locales

  def home(locale), do: "/#{locale}"

  def area(locale, %{"kind" => kind, "slug" => slug}),
    do: area(locale, kind, Locales.pick(slug, locale))

  def area(locale, %{kind: kind} = area),
    do: area(locale, kind, SyliAtlas.Geo.Area.slug(area, locale))

  def area(locale, "country", slug), do: "/#{locale}/#{segment(locale, :country)}/#{slug}"
  def area(locale, _kind, slug), do: "/#{locale}/#{segment(locale, :regions)}/#{slug}"

  @tabs [:overview, :economy, :finances, :trade, :society, :markets]

  @doc "The tabs of a country profile, in page order."
  def tabs, do: @tabs

  @doc "A tab of a country profile; the overview is the profile's own URL."
  def area_tab(locale, area, :overview), do: area(locale, area)
  def area_tab(locale, area, tab), do: area(locale, area) <> "/" <> tab_segment(locale, tab)

  @doc "A tab of a country profile from its slug."
  def country_tab(locale, slug, :overview), do: area(locale, "country", slug)

  def country_tab(locale, slug, tab),
    do: area(locale, "country", slug) <> "/" <> tab_segment(locale, tab)

  @tab_segments %{
    economy: %{"fr" => "economie", "en" => "economy", "es" => "economia", "pt" => "economia"},
    finances: %{
      "fr" => "finances-et-dette",
      "en" => "finances-and-debt",
      "es" => "finanzas-y-deuda",
      "pt" => "financas-e-divida"
    },
    trade: %{"fr" => "commerce", "en" => "trade", "es" => "comercio", "pt" => "comercio"},
    society: %{"fr" => "societe", "en" => "society", "es" => "sociedad", "pt" => "sociedade"},
    markets: %{"fr" => "marches", "en" => "markets", "es" => "mercados", "pt" => "mercados"}
  }

  def tab_segment(locale, tab), do: @tab_segments[tab][Locales.base(locale)]

  @doc "The tab named by a URL segment, in either language, or nil."
  def tab_from_segment(segment) do
    Enum.find(@tabs -- [:overview], fn tab ->
      segment in Map.values(@tab_segments[tab])
    end)
  end

  def communities(locale), do: "/#{locale}/#{segment(locale, :communities)}"
  def community(locale, slug), do: communities(locale) <> "/" <> slug

  def compare(locale, slugs),
    do: "/#{locale}/#{segment(locale, :compare)}/" <> Enum.join(slugs, "/")

  def regions(locale), do: "/#{locale}/#{segment(locale, :regions)}"
  def ranking(locale), do: "/#{locale}/#{segment(locale, :ranking)}"

  @doc "The ranking's main page: GDP (SyliAtlasWeb.Topics.ranking_path/2)."
  def ranking_main(locale), do: SyliAtlasWeb.Topics.ranking_path(locale, "gdp_usd_bn")
  def search(locale), do: "/#{locale}/#{segment(locale, :search)}"
  def method(locale), do: "/#{locale}/#{segment(locale, :method)}"
  def about(locale), do: "/#{locale}/#{segment(locale, :about)}"
  def accessibility(locale), do: "/#{locale}/#{segment(locale, :accessibility)}"
  def offline(locale), do: "/#{locale}/#{segment(locale, :offline)}"
  @doc "The public API documentation: /fr/api, /en/api."
  def api(locale), do: "/#{locale}/api"
  def discussion(locale, area), do: area(locale, area) <> "/discussion"
  @doc "The page to ask for the country recap without an account."
  def recap(locale), do: "/#{account_locale(locale)}/recap"

  def login(locale), do: "/#{account_locale(locale)}/#{segment(account_locale(locale), :login)}"
  def login_code(locale), do: login(locale) <> "/code"
  def admin_key(locale), do: login(locale) <> "/" <> segment(account_locale(locale), :passkey)

  @doc "The member's space: favourites, then `:alerts` and `:security`."
  def account(locale),
    do: "/#{account_locale(locale)}/#{segment(account_locale(locale), :account)}"

  def account(locale, :favorites), do: account(locale)
  def account(locale, tab), do: account(locale) <> "/" <> segment(account_locale(locale), tab)

  @doc "Sign-in and the member's space are in French or English."
  def account_locale("fr"), do: "fr"
  def account_locale(_), do: "en"

  def ratings(locale), do: "/#{locale}/#{segment(locale, :ratings)}"
  def rating(locale, slug), do: ratings(locale) <> "/" <> slug

  def debt(locale), do: "/#{locale}/#{segment(locale, :debt)}"

  def markets(locale), do: "/#{locale}/#{segment(locale, :markets)}"
  def etfs(locale), do: markets(locale) <> "/etf"
  def exchange(locale, code), do: markets(locale) <> "/" <> code

  def security(locale, exchange_code, ticker),
    do: exchange(locale, exchange_code) <> "/" <> String.downcase(ticker)

  def with_period(path, from, to), do: path <> "?from=#{from}&to=#{to}"

  # Path segments of the public pages; Arabic, Hindi and Chinese use the
  # English ones (SyliAtlas.Locales.base/1).
  @segments %{
    country: %{"fr" => "pays", "en" => "countries", "es" => "paises", "pt" => "paises"},
    regions: %{"fr" => "regions", "en" => "regions", "es" => "regiones", "pt" => "regioes"},
    compare: %{"fr" => "comparer", "en" => "compare", "es" => "comparar", "pt" => "comparar"},
    ranking: %{
      "fr" => "classement",
      "en" => "ranking",
      "es" => "clasificacion",
      "pt" => "classificacao"
    },
    search: %{"fr" => "recherche", "en" => "search", "es" => "buscar", "pt" => "pesquisa"},
    method: %{"fr" => "methode", "en" => "method", "es" => "metodo", "pt" => "metodo"},
    about: %{"fr" => "a-propos", "en" => "about", "es" => "acerca-de", "pt" => "sobre"},
    accessibility: %{
      "fr" => "accessibilite",
      "en" => "accessibility",
      "es" => "accesibilidad",
      "pt" => "acessibilidade"
    },
    offline: %{"fr" => "hors-ligne", "en" => "offline", "es" => "sin-conexion", "pt" => "offline"},
    markets: %{
      "fr" => "bourses",
      "en" => "stock-exchanges",
      "es" => "bolsas",
      "pt" => "bolsas"
    },
    ratings: %{
      "fr" => "notations",
      "en" => "credit-ratings",
      "es" => "calificaciones",
      "pt" => "ratings"
    },
    communities: %{
      "fr" => "communautes",
      "en" => "economic-communities",
      "es" => "comunidades-economicas",
      "pt" => "comunidades-economicas"
    },
    debt: %{"fr" => "dette", "en" => "debt", "es" => "deuda", "pt" => "divida"},
    questions: %{
      "fr" => "questions",
      "en" => "questions",
      "es" => "preguntas",
      "pt" => "perguntas"
    },
    glossary: %{"fr" => "glossaire", "en" => "glossary", "es" => "glosario", "pt" => "glossario"},
    # The member's space exists in French and English only.
    login: %{"fr" => "connexion", "en" => "sign-in"},
    passkey: %{"fr" => "cle", "en" => "passkey"},
    account: %{"fr" => "mon-espace", "en" => "my-space"},
    alerts: %{"fr" => "alertes", "en" => "alerts"},
    security: %{"fr" => "securite", "en" => "security"}
  }

  def segment(locale, key) do
    by_locale = Map.fetch!(@segments, key)
    by_locale[Locales.base(locale)] || by_locale["en"]
  end
end
