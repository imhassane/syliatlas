defmodule SyliAtlasWeb.Paths do
  @moduledoc "Localised, readable URLs: /fr/pays/cote-d-ivoire, /en/countries/cote-d-ivoire."

  def home(locale), do: "/#{locale}"

  def area(locale, %{"kind" => kind, "slug" => slug}), do: area(locale, kind, slug[locale])

  def area(locale, %{kind: kind} = area),
    do: area(locale, kind, SyliAtlas.Geo.Area.slug(area, locale))

  def area(locale, "country", slug), do: "/#{locale}/#{segment(locale, :country)}/#{slug}"
  def area(locale, _kind, slug), do: "/#{locale}/regions/#{slug}"

  def compare(locale, slugs),
    do: "/#{locale}/#{segment(locale, :compare)}/" <> Enum.join(slugs, "/")

  def regions(locale), do: "/#{locale}/regions"
  def ranking(locale), do: "/#{locale}/#{segment(locale, :ranking)}"
  def search(locale), do: "/#{locale}/#{segment(locale, :search)}"
  def method(locale), do: "/#{locale}/#{segment(locale, :method)}"
  def discussion(locale, area), do: area(locale, area) <> "/discussion"
  def login(locale), do: "/#{locale}/#{segment(locale, :login)}"

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
  def segment("en", :login), do: "sign-in"
  def segment(_, :login), do: "connexion"
end
