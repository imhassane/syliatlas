defmodule SyliAtlasWeb.Paths do
  @moduledoc "Localised, readable URLs: /fr/pays/cote-d-ivoire, /en/countries/cote-d-ivoire."

  def home(locale), do: "/#{locale}"

  def area(locale, %{"kind" => kind, "slug" => slug}), do: area(locale, kind, slug[locale])

  def area(locale, %{kind: kind} = area),
    do: area(locale, kind, SyliAtlas.Geo.Area.slug(area, locale))

  def area(locale, "country", slug), do: "/#{locale}/#{segment(locale, :country)}/#{slug}"
  def area(locale, _kind, slug), do: "/#{locale}/regions/#{slug}"

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

  def tab_segment("en", :economy), do: "economy"
  def tab_segment(_, :economy), do: "economie"
  def tab_segment("en", :finances), do: "finances-and-debt"
  def tab_segment(_, :finances), do: "finances-et-dette"
  def tab_segment("en", :trade), do: "trade"
  def tab_segment(_, :trade), do: "commerce"
  def tab_segment("en", :society), do: "society"
  def tab_segment(_, :society), do: "societe"
  def tab_segment("en", :markets), do: "markets"
  def tab_segment(_, :markets), do: "marches"

  @doc "The tab named by a URL segment, in either language, or nil."
  def tab_from_segment(segment) do
    Enum.find(@tabs -- [:overview], fn tab ->
      segment in [tab_segment("fr", tab), tab_segment("en", tab)]
    end)
  end

  def communities(locale), do: "/#{locale}/#{segment(locale, :communities)}"
  def community(locale, slug), do: communities(locale) <> "/" <> slug

  def compare(locale, slugs),
    do: "/#{locale}/#{segment(locale, :compare)}/" <> Enum.join(slugs, "/")

  def regions(locale), do: "/#{locale}/regions"
  def ranking(locale), do: "/#{locale}/#{segment(locale, :ranking)}"
  def search(locale), do: "/#{locale}/#{segment(locale, :search)}"
  def method(locale), do: "/#{locale}/#{segment(locale, :method)}"
  def offline(locale), do: "/#{locale}/#{segment(locale, :offline)}"
  def discussion(locale, area), do: area(locale, area) <> "/discussion"
  def login(locale), do: "/#{locale}/#{segment(locale, :login)}"
  def login_code(locale), do: login(locale) <> "/code"
  def admin_key(locale), do: login(locale) <> "/" <> segment(locale, :passkey)

  @doc "The member's space: favourites, then `:alerts` and `:security`."
  def account(locale), do: "/#{locale}/#{segment(locale, :account)}"
  def account(locale, :favorites), do: account(locale)
  def account(locale, tab), do: account(locale) <> "/" <> segment(locale, tab)

  def ratings(locale), do: "/#{locale}/#{segment(locale, :ratings)}"
  def rating(locale, slug), do: ratings(locale) <> "/" <> slug

  def debt(locale), do: "/#{locale}/#{segment(locale, :debt)}"

  def markets(locale), do: "/#{locale}/#{segment(locale, :markets)}"
  def etfs(locale), do: markets(locale) <> "/etf"
  def exchange(locale, code), do: markets(locale) <> "/" <> code

  def security(locale, exchange_code, ticker),
    do: exchange(locale, exchange_code) <> "/" <> String.downcase(ticker)

  def with_period(path, from, to), do: path <> "?from=#{from}&to=#{to}"

  def segment("en", :country), do: "countries"
  def segment(_, :country), do: "pays"
  def segment("en", :compare), do: "compare"
  def segment(_, :compare), do: "comparer"
  def segment("en", :ranking), do: "ranking"
  def segment(_, :ranking), do: "classement"
  def segment("en", :search), do: "search"
  def segment(_, :search), do: "recherche"
  def segment("en", :method), do: "method"
  def segment(_, :method), do: "methode"
  def segment("en", :offline), do: "offline"
  def segment(_, :offline), do: "hors-ligne"
  def segment("en", :markets), do: "stock-exchanges"
  def segment(_, :markets), do: "bourses"
  def segment("en", :ratings), do: "credit-ratings"
  def segment(_, :ratings), do: "notations"
  def segment("en", :communities), do: "economic-communities"
  def segment(_, :communities), do: "communautes"
  def segment("en", :debt), do: "debt"
  def segment(_, :debt), do: "dette"
  def segment("en", :login), do: "sign-in"
  def segment(_, :login), do: "connexion"
  def segment("en", :passkey), do: "passkey"
  def segment(_, :passkey), do: "cle"
  def segment("en", :account), do: "my-space"
  def segment(_, :account), do: "mon-espace"
  def segment("en", :alerts), do: "alerts"
  def segment(_, :alerts), do: "alertes"
  def segment("en", :security), do: "security"
  def segment(_, :security), do: "securite"
end
