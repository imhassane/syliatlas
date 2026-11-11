defmodule SyliAtlas.Geo.Names do
  @moduledoc """
  Names of the areas beyond French and English (priv/data/area_names.json),
  and the Spanish and Portuguese slugs made from them. Loaded once.
  """

  @key {__MODULE__, :names}

  def path, do: Application.app_dir(:syli_atlas, "priv/data/area_names.json")

  defp data do
    case :persistent_term.get(@key, nil) do
      nil ->
        names = path() |> File.read!() |> Jason.decode!() |> Map.delete("_note")

        slugs =
          for {code, by_locale} <- names, locale <- ["es", "pt"], into: %{} do
            {{code, locale}, slugify(by_locale[locale])}
          end

        data = %{
          names: names,
          slugs: slugs,
          codes: Map.new(slugs, fn {{c, l}, s} -> {{l, s}, c} end)
        }

        :persistent_term.put(@key, data)
        data

      data ->
        data
    end
  end

  @doc "The name of the area `code` in `locale` (es, pt, ar, hi, zh), or nil."
  def name(code, locale), do: get_in(data(), [:names, code, locale])

  @doc "The Spanish or Portuguese slug of an area, or nil."
  def slug(code, locale), do: data().slugs[{code, locale}]

  @doc "The area code of a Spanish or Portuguese slug, or nil."
  def code_for_slug(slug, locale), do: data().codes[{locale, slug}]

  @doc "« São Tomé e Príncipe » → « sao-tome-e-principe »."
  def slugify(name) do
    name
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
