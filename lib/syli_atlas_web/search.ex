defmodule SyliAtlasWeb.Search do
  @moduledoc """
  The site search, in Elixir, over the in-memory index
  (`SyliAtlasWeb.Search.Index`).

  A query is normalised, split into words, and cut into:

    * topic words (« dette », « inflation », « bourse »…) that point to a
      tab of the country profile and, when there is one, an indicator;
    * the rest, matched against the names of the index: exact, then
      prefix, then contained, then typo-tolerant (Jaro distance ≥ 0.88 on
      words of four letters or more).

  « dette sénégal » therefore leads to the Finances and debt tab of Senegal,
  with the figure itself as the direct answer, taken from the precomputed
  profile (`PublicData.area/3`).
  """

  use Gettext, backend: SyliAtlasWeb.Gettext

  alias SyliAtlasWeb.{Format, Paths, PublicData}
  alias SyliAtlasWeb.Search.Index

  @year 2025
  @limit 12

  @stopwords ~w(de du des la le les l d en au aux a et un une pour sur dans quel quelle quels quelles est sont
                the of in on for and what is are a an to)

  # word → {tab, indicator or nil}
  @topics %{
    "dette" => {:finances, "public_debt_pct_gdp"},
    "debt" => {:finances, "public_debt_pct_gdp"},
    "endettement" => {:finances, "public_debt_pct_gdp"},
    "deficit" => {:finances, "fiscal_balance_pct_gdp"},
    "budget" => {:finances, "fiscal_balance_pct_gdp"},
    "budgetaire" => {:finances, "fiscal_balance_pct_gdp"},
    "finances" => {:finances, nil},
    "monnaie" => {:finances, nil},
    "currency" => {:finances, nil},
    "cfa" => {:finances, nil},
    "inflation" => {:economy, "inflation"},
    "prix" => {:economy, "inflation"},
    "prices" => {:economy, "inflation"},
    "croissance" => {:economy, "real_gdp_growth"},
    "growth" => {:economy, "real_gdp_growth"},
    "pib" => {:economy, "gdp_usd_bn"},
    "gdp" => {:economy, "gdp_usd_bn"},
    "economie" => {:economy, nil},
    "economy" => {:economy, nil},
    "population" => {:economy, "population_m"},
    "habitants" => {:economy, "population_m"},
    "commerce" => {:trade, nil},
    "trade" => {:trade, nil},
    "exportations" => {:trade, nil},
    "exports" => {:trade, nil},
    "importations" => {:trade, nil},
    "imports" => {:trade, nil},
    "clients" => {:trade, nil},
    "chomage" => {:society, "unemployment"},
    "unemployment" => {:society, "unemployment"},
    "emploi" => {:society, nil},
    "jobs" => {:society, nil},
    "pauvrete" => {:society, nil},
    "poverty" => {:society, nil},
    "electricite" => {:society, nil},
    "electricity" => {:society, nil},
    "societe" => {:society, nil},
    "society" => {:society, nil},
    "notation" => {:markets, nil},
    "note" => {:markets, nil},
    "rating" => {:markets, nil},
    "bourse" => {:markets, nil},
    "stock" => {:markets, nil},
    "marches" => {:markets, nil},
    "markets" => {:markets, nil},
    "climat" => {:markets, nil}
  }

  @doc """
  Results for a query, as plain maps ready for JSON:

      %{"query" => "dette senegal", "answer" => %{...} | nil,
        "exact" => true,  # the first result is the only full match
        "results" => [%{"type" => "country", "label" => ..., "path" => ..., ...}]}
  """
  def run(query, locale) do
    q = query |> to_string() |> String.slice(0, 80) |> Index.normalize()
    all_words = String.split(q)
    {topic_words, kept} = Enum.split_with(all_words, &Map.has_key?(@topics, &1))
    topic = topic_words |> Enum.map(&@topics[&1]) |> List.first()
    # « afrique de l'ouest » is matched with its small words, « dette du
    # sénégal » without them: both forms are tried.
    full = kept |> drop_edge_stopwords() |> Enum.join(" ")
    text = kept |> Enum.reject(&(&1 in @stopwords)) |> Enum.join(" ")

    scored =
      cond do
        text != "" -> match(Index.get(), Enum.uniq([full, text]))
        topic_words != [] -> match(Index.get(), [Enum.join(topic_words, " ")])
        true -> []
      end

    hits = Enum.map(scored, &elem(&1, 1))

    exact =
      case scored do
        [{100, _}, {100, _} | _] -> false
        [{100, _} | _] -> true
        _ -> false
      end

    results =
      hits
      |> Enum.take(@limit)
      |> Enum.map(&result(&1, topic, locale))

    %{
      "query" => q,
      "topic" => topic && Atom.to_string(elem(topic, 0)),
      "answer" => answer(hits, topic, text, locale),
      "exact" => exact,
      "results" => results
    }
  end

  @doc "True when the search found nothing (logged for the admin)."
  def miss?(%{"results" => []}), do: true
  def miss?(_), do: false

  defp drop_edge_stopwords(words) do
    words
    |> Enum.drop_while(&(&1 in @stopwords))
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 in @stopwords))
    |> Enum.reverse()
  end

  defp match(entries, texts) do
    entries
    |> Enum.map(fn e -> {texts |> Enum.map(&score(e, &1)) |> Enum.max(), e} end)
    |> Enum.filter(fn {s, _} -> s > 0 end)
    |> Enum.sort_by(fn {s, e} -> {-s, e.rank, e.names["fr"]} end)
  end

  defp score(entry, text) do
    entry.terms |> Enum.map(&term_score(&1, text)) |> Enum.max(fn -> 0 end)
  end

  defp term_score(term, text) do
    cond do
      term == text ->
        100

      String.starts_with?(term, text) and String.length(text) >= 2 ->
        80 - min(String.length(term) - String.length(text), 30) / 2

      String.length(text) >= 3 and Enum.any?(String.split(term), &String.starts_with?(&1, text)) ->
        60

      all_words?(term, text) ->
        70

      String.length(text) >= 4 and String.contains?(term, text) ->
        50

      String.length(text) >= 4 ->
        fuzzy(term, text)

      true ->
        0
    end
  end

  # Several words, each the start of a word of the name, in any order:
  # « afrique ouest », « guinee equat ».
  defp all_words?(term, text) do
    case String.split(text) do
      [_, _ | _] = words ->
        tw = String.split(term)
        Enum.all?(words, fn w -> Enum.any?(tw, &String.starts_with?(&1, w)) end)

      _ ->
        false
    end
  end

  # Typo tolerance: the whole query against the whole name, or each word of
  # the query against a word of the name.
  defp fuzzy(term, text) do
    whole = String.jaro_distance(term, text)

    words =
      for w <- String.split(text), String.length(w) >= 4 do
        term |> String.split() |> Enum.map(&String.jaro_distance(&1, w)) |> Enum.max(fn -> 0 end)
      end

    best = Enum.max([whole | words])
    if best >= 0.88, do: round(best * 40), else: 0
  end

  defp result(%{type: :country} = e, {tab, _}, locale) do
    tab_path = Paths.country_tab(locale, e.slug[locale], tab)

    base(e, locale)
    |> Map.merge(%{
      "path" => tab_path,
      "label" => "#{e.names[locale]} · #{SyliAtlasWeb.ProfileComponents.tab_label(tab)}",
      "profile" => e.path[locale]
    })
  end

  defp result(e, _topic, locale), do: base(e, locale)

  defp base(e, locale) do
    %{
      "type" => Atom.to_string(e.type),
      "code" => e.code,
      "label" => e.names[locale],
      "kind" => kind_label(e.type),
      "path" => e.path[locale]
    }
  end

  defp kind_label(:country), do: gettext("Country")
  defp kind_label(:region), do: gettext("Region")
  defp kind_label(:community), do: gettext("Community")
  defp kind_label(:page), do: gettext("Theme")
  defp kind_label(:exchange), do: gettext("Stock exchange")
  defp kind_label(:security), do: gettext("Security")

  # The figure itself when the first hit is a country or a region named in
  # full (not a two-letter prefix): its debt for « dette sénégal », its GDP
  # and growth for « sénégal ».
  defp answer([%{type: type} = e | _], topic, text, locale)
       when type in [:country, :region] and byte_size(text) >= 3 do
    indicator =
      case topic do
        {_, key} when is_binary(key) -> key
        nil -> "gdp_usd_bn"
        _ -> nil
      end

    with true <- is_binary(indicator),
         %{"profile" => %{"series" => series}} <- PublicData.area(e.code, 2020, @year),
         v when is_number(v) <- PublicData.at(series[indicator], @year) do
      extra =
        if indicator == "gdp_usd_bn",
          do: PublicData.at(series["real_gdp_growth"], @year),
          else: nil

      path =
        case {type, topic} do
          {:country, {tab, _}} -> Paths.country_tab(locale, e.slug[locale], tab)
          {:country, nil} -> Paths.country_tab(locale, e.slug[locale], :economy)
          _ -> e.path[locale]
        end

      %{
        "name" => e.names[locale],
        "indicator" => indicator,
        "label" => SyliAtlasWeb.PageComponents.indicator_label(indicator),
        "value" => Format.value(v, indicator, locale),
        "year" => @year,
        "growth" => extra && Format.value(extra, "real_gdp_growth", locale),
        "source" => gettext("IMF, World Economic Outlook"),
        "path" => path
      }
    else
      _ -> nil
    end
  end

  defp answer(_hits, _topic, _text, _locale), do: nil
end
