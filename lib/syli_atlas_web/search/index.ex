defmodule SyliAtlasWeb.Search.Index do
  @moduledoc """
  What the site search can find, built once from the data and kept in
  `:persistent_term`: countries (with their usual other names and ISO
  codes), regions, communities, theme pages, exchanges and their
  securities (while the market data may be shown).

  The index is rebuilt when the IMF data or the market data change: its key
  carries both data versions, so a new edition is searchable at once.

  Each entry:

      %{type: :country, code: "CIV", names: %{"fr" => ..., "en" => ...},
        terms: ["cote d'ivoire", "ivory coast", "civ", ...],
        path: %{"fr" => "/fr/pays/cote-d-ivoire", "en" => ...},
        rank: 0}

  `terms` are normalised (no accents, lower case, no punctuation) and
  `rank` breaks ties (lower first). `keys` holds the same terms with their
  words and length computed once, so that a query costs no splitting.
  """

  alias SyliAtlas.Economy.Communities
  alias SyliAtlas.Geo.Area
  alias SyliAtlasWeb.Paths

  @key {__MODULE__, :index}

  # Other names people type: former names, English or French usage,
  # acronyms. The ISO code and both official names are added for all.
  @aliases %{
    "CIV" => ["ivory coast", "cote divoire", "rci", "coast d'ivoire"],
    "COD" => [
      "rdc",
      "drc",
      "congo kinshasa",
      "zaire",
      "republique democratique du congo",
      "democratic republic of congo"
    ],
    "COG" => ["congo brazzaville", "republique du congo", "republic of congo"],
    "CAF" => ["rca", "car", "centrafrique"],
    "CPV" => ["cap vert", "cape verde", "cabo verde"],
    "GNQ" => ["guinee equatoriale", "equatorial guinea"],
    "GNB" => ["guinee bissau", "guinea bissau"],
    "GIN" => ["guinee conakry", "guinea conakry"],
    "SWZ" => ["swaziland", "eswatini"],
    "STP" => ["sao tome", "sao tome et principe", "sao tome and principe"],
    "ZAF" => ["rsa", "south africa", "afrique du sud"],
    "SSD" => ["south sudan", "soudan du sud"],
    "TZA" => ["tanzanie", "tanzania"],
    "GMB" => ["gambie", "the gambia"],
    "EGY" => ["egypte", "egypt"],
    "MAR" => ["maroc", "morocco"],
    "DZA" => ["algerie", "algeria"],
    "TUN" => ["tunisie", "tunisia"],
    "LBY" => ["libye", "libya"],
    "ETH" => ["ethiopie", "ethiopia"],
    "SOM" => ["somalie", "somalia"],
    "MRT" => ["mauritanie", "mauritania"],
    "MUS" => ["maurice", "ile maurice", "mauritius"],
    "SYC" => ["seychelles"],
    "COM" => ["comores", "comoros"],
    "BFA" => ["haute volta", "burkina"],
    "BEN" => ["dahomey"],
    "BWA" => ["botswana"],
    "LSO" => ["lesotho"]
  }

  @doc "The current index, rebuilt when the data changed."
  def get, do: elem(cached(), 0)

  @doc """
  The entries that may match these query words: those with a word that
  starts with the same `n` letters as one of them (n = 2 for the exact
  pass, 1 for the typo-tolerant pass). Avoids comparing every security.
  """
  def candidates(query_words, n) when n in [1, 2] do
    %{prefixes: prefixes, entries: entries} = elem(cached(), 1)
    table = prefixes[n]

    query_words
    |> Enum.map(&binary_part(&1, 0, min(n, byte_size(&1))))
    |> Enum.uniq()
    |> Enum.flat_map(&Map.get(table, &1, []))
    |> Enum.uniq()
    |> Enum.map(&elem(entries, &1))
  end

  @doc """
  What the footer of every page needs, kept with the index so that a page
  costs no query for it: the IMF edition label and the exchanges shown.
  """
  def meta, do: elem(cached(), 1)

  defp cached do
    version = version()

    case :persistent_term.get(@key, nil) do
      {^version, entries, meta} ->
        {entries, meta}

      _ ->
        entries = build()
        meta = build_meta(entries)
        :persistent_term.put(@key, {version, entries, meta})
        {entries, meta}
    end
  end

  @doc false
  def build_meta(entries) do
    edition = SyliAtlas.Sources.published_edition("imf_weo")

    indexed = Enum.with_index(entries)

    prefixes =
      Map.new([1, 2], fn n ->
        table =
          for {e, i} <- indexed, k <- e.keys, w <- k.words, byte_size(w) >= 1, reduce: %{} do
            acc -> Map.update(acc, binary_part(w, 0, min(n, byte_size(w))), [i], &[i | &1])
          end

        {n, Map.new(table, fn {p, is} -> {p, is |> Enum.uniq() |> Enum.reverse()} end)}
      end)

    %{
      entries: List.to_tuple(entries),
      prefixes: prefixes,
      edition: edition && edition.label,
      exchanges:
        for %{type: :exchange} = e <- entries do
          %{code: e.code, short_name: e.short_name, path: e.path}
        end
    }
  end

  @doc "Forget the index (tests, after a data import)."
  def reset, do: :persistent_term.erase(@key)

  defp version do
    {SyliAtlas.Profiles.data_version(), SyliAtlas.Market.data_version(),
     SyliAtlas.Market.public?()}
  end

  @doc false
  def build do
    areas = SyliAtlas.Geo.list_areas()

    (countries(areas) ++ regions(areas) ++ communities() ++ pages() ++ market())
    |> Enum.map(fn e -> Map.put(e, :keys, Enum.map(e.terms, &key/1)) end)
  end

  @doc "A term with its words and its length, as the matcher wants it."
  def key(term) do
    words = :binary.split(term, " ", [:global])
    %{t: term, words: words, len: String.length(term)}
  end

  defp countries(areas) do
    for a <- areas, a.kind == "country" do
      %{
        type: :country,
        code: a.code,
        names: Area.names(a),
        terms:
          terms(
            Map.values(Area.names(a)) ++
              [a.code, a.slug_fr, a.slug_en | Map.get(@aliases, a.code, [])]
          ),
        path: SyliAtlas.Locales.each(fn l -> Paths.area(l, a) end),
        slug: %{"fr" => a.slug_fr, "en" => a.slug_en},
        rank: 0
      }
    end
  end

  defp regions(areas) do
    for a <- areas, a.kind != "country" do
      %{
        type: :region,
        code: a.code,
        names: Area.names(a),
        terms: terms(Map.values(Area.names(a)) ++ [a.slug_fr, a.slug_en]),
        path: SyliAtlas.Locales.each(fn l -> Paths.area(l, a) end),
        kind: a.kind,
        rank: if(a.kind == "region", do: 1, else: 2)
      }
    end
  end

  defp communities do
    for c <- Communities.all() do
      %{
        type: :community,
        code: c.code,
        names:
          SyliAtlas.Locales.each(fn l ->
            "#{SyliAtlas.Locales.pick(c.short, l)} · #{SyliAtlas.Locales.pick(c.name, l)}"
          end),
        terms: terms(Map.values(c.short) ++ Map.values(c.name) ++ [c.code]),
        path:
          SyliAtlas.Locales.each(fn l ->
            Paths.community(l, SyliAtlas.Locales.pick(c.slug, l))
          end),
        rank: 1
      }
    end
  end

  # Theme pages, found by their name or by the words people use for them.
  defp pages do
    [
      {:debt, &Paths.debt/1,
       %{
         "fr" => "Dette des pays africains",
         "en" => "Debt of African countries",
         "es" => "Deuda de los países africanos",
         "pt" => "Dívida dos países africanos",
         "ar" => "ديون الدول الأفريقية",
         "hi" => "अफ़्रीकी देशों का ऋण",
         "zh" => "非洲国家债务"
       },
       [
         "dette",
         "debt",
         "endettement",
         "surendettement",
         "creanciers",
         "creditors",
         "chine dette"
       ]},
      {:ratings, &Paths.ratings/1,
       %{
         "fr" => "Notations souveraines",
         "en" => "Sovereign credit ratings",
         "es" => "Calificaciones soberanas",
         "pt" => "Ratings soberanos",
         "ar" => "التصنيفات السيادية",
         "hi" => "संप्रभु क्रेडिट रेटिंग",
         "zh" => "主权信用评级"
       },
       [
         "notation",
         "notations",
         "note souveraine",
         "rating",
         "ratings",
         "credit rating",
         "moody's",
         "s&p",
         "fitch",
         "agences de notation"
       ]},
      {:communities, &Paths.communities/1,
       %{
         "fr" => "Communautés économiques",
         "en" => "Economic communities",
         "es" => "Comunidades económicas",
         "pt" => "Comunidades económicas",
         "ar" => "المجموعات الاقتصادية",
         "hi" => "आर्थिक समुदाय",
         "zh" => "经济共同体"
       },
       [
         "communautes",
         "communautes economiques",
         "economic communities",
         "zone franc",
         "franc cfa",
         "cfa"
       ]},
      {:regions, &Paths.regions/1,
       %{
         "fr" => "Régions d'Afrique",
         "en" => "Regions of Africa",
         "es" => "Regiones de África",
         "pt" => "Regiões de África",
         "ar" => "مناطق أفريقيا",
         "hi" => "अफ़्रीका के क्षेत्र",
         "zh" => "非洲各地区"
       }, ["regions", "region", "regions d'afrique"]},
      {:ranking, &Paths.ranking/1,
       %{
         "fr" => "Classement des pays africains",
         "en" => "Ranking of African countries",
         "es" => "Clasificación de los países africanos",
         "pt" => "Classificação dos países africanos",
         "ar" => "ترتيب الدول الأفريقية",
         "hi" => "अफ़्रीकी देशों की रैंकिंग",
         "zh" => "非洲国家排名"
       },
       [
         "classement",
         "ranking",
         "pays",
         "countries",
         "tous les pays",
         "palmares",
         "plus riche",
         "richest"
       ]},
      {:compare, &Paths.compare(&1, []),
       %{
         "fr" => "Comparer des pays",
         "en" => "Compare countries",
         "es" => "Comparar países",
         "pt" => "Comparar países",
         "ar" => "مقارنة الدول",
         "hi" => "देशों की तुलना",
         "zh" => "国家比较"
       }, ["comparer", "compare", "comparaison", "comparison", "versus", "vs"]},
      {:method, &Paths.method/1,
       %{
         "fr" => "Méthode et sources",
         "en" => "Method and sources",
         "es" => "Método y fuentes",
         "pt" => "Método e fontes",
         "ar" => "المنهجية والمصادر",
         "hi" => "पद्धति और स्रोत",
         "zh" => "方法与来源"
       }, ["methode", "method", "sources", "licence", "license", "api", "donnees", "data"]}
    ]
    |> Kernel.++(
      if SyliAtlas.Market.public?(),
        do: [
          {:markets, &Paths.markets/1,
           %{
             "fr" => "Bourses africaines",
             "en" => "African stock exchanges",
             "es" => "Bolsas africanas",
             "pt" => "Bolsas africanas",
             "ar" => "البورصات الأفريقية",
             "hi" => "अफ़्रीकी शेयर बाज़ार",
             "zh" => "非洲证券交易所"
           },
           [
             "bourse",
             "bourses",
             "stock exchange",
             "stock exchanges",
             "marche boursier",
             "actions",
             "stocks",
             "indice"
           ]}
        ],
        else: []
    )
    |> Enum.map(fn {code, path, names, words} ->
      %{
        type: :page,
        code: Atom.to_string(code),
        names: names,
        terms: terms(Map.values(names) ++ words),
        path: SyliAtlas.Locales.each(fn l -> path.(l) end),
        rank: 2
      }
    end)
  end

  defp market do
    with true <- SyliAtlas.Market.public?(),
         %{"exchanges" => exchanges} <- SyliAtlas.Market.overview() do
      Enum.flat_map(exchanges, fn %{"exchange" => e} ->
        exchange = %{
          type: :exchange,
          code: e["code"],
          short_name: e["short_name"],
          names: SyliAtlas.Locales.each(fn _ -> "#{e["short_name"]} · #{e["name"]}" end),
          terms: terms([e["short_name"], e["name"], e["code"], e["index_name"], e["mic"]]),
          path: SyliAtlas.Locales.each(fn l -> Paths.exchange(l, e["code"]) end),
          rank: 2
        }

        securities =
          case SyliAtlas.Market.exchange(e["code"]) do
            %{"securities" => rows} ->
              for s <- rows, s["current"] != false do
                label = "#{s["name"]} (#{s["ticker"]}, #{e["short_name"]})"

                %{
                  type: :security,
                  code: "#{e["code"]}:#{s["ticker"]}",
                  names: SyliAtlas.Locales.each(fn _ -> label end),
                  terms: terms([s["name"], s["ticker"], s["issuer"], s["isin"]]),
                  path:
                    SyliAtlas.Locales.each(fn l -> Paths.security(l, e["code"], s["ticker"]) end),
                  rank: 3
                }
              end

            _ ->
              []
          end

        [exchange | securities]
      end)
    else
      _ -> []
    end
  end

  defp terms(list) do
    list
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.map(&normalize/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  @doc "Lower case, no accents, punctuation and hyphens as spaces."
  def normalize(text) do
    text
    |> to_string()
    |> Area.normalize()
    |> String.replace(~r/[’'`]/u, " ")
    |> String.replace(~r/[^\p{L}\p{N}&]+/u, " ")
    |> String.split()
    |> Enum.join(" ")
  end
end
