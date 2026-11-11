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
        text != "" -> match(Enum.uniq([full, text]))
        topic_words != [] -> match([Enum.join(topic_words, " ")])
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

  # Two passes: names that start, contain or equal the query, then, only if
  # none did, the typo-tolerant pass.
  defp match(texts) do
    queries = Enum.map(texts, &Index.key/1)
    words = queries |> Enum.flat_map(& &1.words) |> Enum.uniq()

    case rank(Index.candidates(words, 2), queries, &exact_score/2) do
      [] -> rank(Index.candidates(words, 1), queries, &fuzzy_score/2)
      hits -> hits
    end
  end

  defp rank(entries, queries, fun) do
    entries
    |> Enum.map(fn e -> {best(e.keys, queries, fun), e} end)
    |> Enum.filter(fn {s, _} -> s > 0 end)
    |> Enum.sort_by(fn {s, e} -> {-s, e.rank, e.names["fr"]} end)
  end

  defp best(keys, queries, fun) do
    Enum.reduce(keys, 0, fn k, acc ->
      Enum.reduce(queries, acc, fn q, acc2 -> max(acc2, fun.(k, q)) end)
    end)
  end

  defp exact_score(%{t: t}, %{t: t}), do: 100

  defp exact_score(k, q) do
    cond do
      q.len >= 2 and String.starts_with?(k.t, q.t) ->
        80 - min(k.len - q.len, 30) / 2

      q.len >= 3 and Enum.any?(k.words, &String.starts_with?(&1, q.t)) ->
        60

      all_words?(k, q) ->
        70

      q.len >= 4 and String.contains?(k.t, q.t) ->
        50

      true ->
        0
    end
  end

  # Several words, each the start of a word of the name, in any order:
  # « afrique ouest », « guinee equat ».
  defp all_words?(k, %{words: [_, _ | _] = words}),
    do: Enum.all?(words, fn w -> Enum.any?(k.words, &String.starts_with?(&1, w)) end)

  defp all_words?(_k, _q), do: false

  # Typo tolerance: the whole query against the whole name, or each word of
  # the query (four letters or more) against a word of the name.
  defp fuzzy_score(_k, %{len: len}) when len < 4, do: 0

  defp fuzzy_score(k, q) do
    whole = String.jaro_distance(k.t, q.t)

    best =
      for w <- q.words, byte_size(w) >= 4, kw <- k.words, reduce: whole do
        acc -> max(acc, String.jaro_distance(kw, w))
      end

    if best >= 0.88, do: round(best * 40), else: 0
  end

  defp result(%{type: :country} = e, {tab, _}, locale) do
    tab_path = Paths.country_tab(locale, SyliAtlas.Locales.pick(e.slug, locale), tab)

    base(e, locale)
    |> Map.merge(%{
      "path" => tab_path,
      "label" =>
        "#{SyliAtlas.Locales.pick(e.names, locale)} · #{SyliAtlasWeb.ProfileComponents.tab_label(tab)}",
      "profile" => e.path[locale]
    })
  end

  defp result(e, _topic, locale), do: base(e, locale)

  defp base(e, locale) do
    %{
      "type" => Atom.to_string(e.type),
      "code" => e.code,
      "label" => SyliAtlas.Locales.pick(e.names, locale),
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
          {:country, {tab, _}} ->
            Paths.country_tab(locale, SyliAtlas.Locales.pick(e.slug, locale), tab)

          {:country, nil} ->
            Paths.country_tab(locale, SyliAtlas.Locales.pick(e.slug, locale), :economy)

          _ ->
            e.path[locale]
        end

      %{
        "name" => SyliAtlas.Locales.pick(e.names, locale),
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
