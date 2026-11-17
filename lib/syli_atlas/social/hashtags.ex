defmodule SyliAtlas.Social.Hashtags do
  @moduledoc """
  Hashtags added to a draft when it is prepared, so they stay editable in
  the admin like the rest of the text.

  Since LinkedIn dropped hashtag following (2024), tags no longer bring
  reach on their own; they classify the post and make it findable when
  someone searches the tag. So few and precise:

    * X: three, the country (or the subject) then #Africa #Economy, at the
      end of the first paragraph (before the call to action and the link).
      Past 280 characters, #Africa #Economy alone, then none.
    * LinkedIn: four, in French: country, subject, #Afrique #Économie, as
      the last paragraph (the link follows them).
  """
  alias SyliAtlas.Geo
  alias SyliAtlas.Geo.Area
  alias SyliAtlas.Social.Post

  # On every post.
  @base_en ~w(#Africa #Economy)
  @base_fr ~w(#Afrique #Économie)

  # Names that make a poor tag once squeezed into one word.
  @short %{
    "en" => %{"COD" => "DRC", "COG" => "CongoBrazzaville", "CAF" => "CAR", "CIV" => "IvoryCoast"},
    "fr" => %{
      "COD" => "RDC",
      "COG" => "CongoBrazzaville",
      "CAF" => "Centrafrique",
      "CIV" => "CôteDIvoire",
      "GNQ" => "GuinéeÉquatoriale",
      "STP" => "SaoToméEtPrincipe"
    }
  }

  @doc "The draft's attributes with their hashtags."
  def add(%{} = attrs) do
    x = tags(attrs, "en")
    li = tags(attrs, "fr")

    attrs
    |> Map.update(:text_x, nil, &tag_x(&1, x, attrs[:link_x]))
    |> Map.update(:text_linkedin, nil, &tag_linkedin(&1, li))
  end

  @doc "The tags of a draft for a locale (en: X, fr: LinkedIn)."
  def tags(attrs, locale) do
    country = country(attrs[:area_code], locale)

    case locale do
      # X: the country (or the subject when there is none), then the two
      # tags every post carries.
      "en" ->
        Enum.reject([country || subject(attrs[:kind], attrs[:key], "en")] ++ @base_en, &is_nil/1)

      # LinkedIn: room for the country and the subject as well.
      "fr" ->
        Enum.reject([country, subject(attrs[:kind], attrs[:key], "fr")] ++ @base_fr, &is_nil/1)
    end
    |> Enum.uniq()
  end

  defp subject("rating", _, "en"), do: "#CreditRating"
  defp subject("rating", _, "fr"), do: "#NotationSouveraine"
  defp subject("budget_law", _, "en"), do: "#Budget"
  defp subject("budget_law", _, "fr"), do: "#LoiDeFinances"
  defp subject("edition", _, "en"), do: "#IMF"
  defp subject("edition", _, "fr"), do: "#FMI"
  defp subject("rebasing", _, "en"), do: "#GDP"
  defp subject("rebasing", _, "fr"), do: "#PIB"

  defp subject("national", key, locale) do
    debt? = is_binary(key) and String.contains?(key, ":public_debt_pct_gdp:")

    case {debt?, locale} do
      {true, "en"} -> "#PublicDebt"
      {true, "fr"} -> "#DettePublique"
      {false, "en"} -> "#GDP"
      {false, "fr"} -> "#PIB"
    end
  end

  defp subject(_, _, _), do: nil

  defp country(nil, _), do: nil

  defp country(code, locale) do
    case @short[locale][code] do
      nil ->
        case Geo.get_area_by_code(code) do
          nil -> nil
          area -> area |> Area.name(locale) |> squeeze()
        end

      short ->
        "#" <> short
    end
  end

  # « Burkina Faso » → #BurkinaFaso, « Guinée-Bissau » → #GuinéeBissau.
  defp squeeze(nil), do: nil

  defp squeeze(name) do
    tag =
      name
      |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
      |> Enum.map_join(&upcase_first/1)

    if tag == "", do: nil, else: "#" <> tag
  end

  defp upcase_first(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest

  # The tags close the first paragraph: on the same line when it is one
  # line, on their own line otherwise (a list). Never past 280 characters.
  defp tag_x(text, [], _link), do: text

  defp tag_x(text, tags, link) do
    {head, rest} =
      case String.split(text, "\n\n", parts: 2) do
        [head, rest] -> {head, "\n\n" <> rest}
        [head] -> {head, ""}
      end

    sep = if String.contains?(head, "\n"), do: "\n", else: " "
    tagged = head <> sep <> Enum.join(tags, " ") <> rest

    cond do
      Post.x_length(tagged, link) <= Post.x_limit() -> tagged
      # Too long: the two common tags alone, then nothing.
      tags != @base_en -> tag_x(text, @base_en, link)
      true -> text
    end
  end

  defp tag_linkedin(text, []), do: text
  defp tag_linkedin(text, tags), do: text <> "\n\n" <> Enum.join(tags, " ")
end
