defmodule SyliAtlasWeb.RatingsController do
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Geo.Area
  alias SyliAtlas.Ratings
  alias SyliAtlas.Ratings.Scale
  alias SyliAtlasWeb.{NotFoundError, Paths, RatingComponents, Seo}
  import SyliAtlasWeb.Format, only: [names: 1, names: 2]

  plug :put_layout, false

  @tabs Scale.bands() ++ ["unrated"]

  @doc "The 54 countries and their ratings, filtered by verdict or searched by name or rating."
  def index(conn, params) do
    locale = conn.assigns.locale
    paths = SyliAtlas.Locales.each(fn l -> Paths.ratings(l) end)
    doc = Ratings.document() || empty()
    verdict = if params["verdict"] in @tabs, do: params["verdict"]
    q = params |> Map.get("q", "") |> String.trim() |> String.slice(0, 60)

    ranked =
      doc["ranking"]
      |> Enum.map(&doc["countries"][&1])

    unrated =
      doc["unrated"]
      |> Enum.map(&doc["countries"][&1])
      |> Enum.sort_by(&Area.normalize(SyliAtlas.Locales.pick(&1["name"], locale)))

    rows =
      case verdict do
        "unrated" -> unrated
        nil -> ranked
        band -> Enum.filter(ranked, &(&1["band"] == band))
      end
      |> search(q, locale)

    counts = Map.merge(doc["counts"], %{nil => doc["rated"], "unrated" => length(unrated)})
    answer = answer(doc, locale)
    faq = faq(doc, locale)

    render(conn, :index,
      page_title: gettext("Sovereign ratings of the 54 African countries (S&P, Moody's, Fitch)"),
      seo:
        Seo.page(locale, paths, answer, %{
          json_ld: [
            Seo.breadcrumbs([
              {"Syli Atlas", Paths.home(locale)},
              {gettext("Sovereign ratings"), paths[locale]}
            ]),
            dataset(doc, paths[locale]),
            Seo.faq(faq)
          ]
        }),
      alternates: Seo.alternates_for_header(paths),
      doc: doc,
      rows: rows,
      unrated: unrated,
      verdict: verdict,
      q: q,
      tabs: [nil | @tabs],
      counts: counts,
      answer: answer,
      faq: faq
    )
  end

  @doc "One country: its verdict, the current rating of each agency and every decision recorded."
  def show(conn, %{"slug" => slug}) do
    locale = conn.assigns.locale
    doc = Ratings.document() || raise NotFoundError

    entry =
      doc["countries"]
      |> Map.values()
      |> Enum.find(&(SyliAtlas.Locales.pick(&1["slug"], locale) == slug)) ||
        raise NotFoundError

    name = SyliAtlas.Locales.pick(entry["name"], locale)

    paths =
      SyliAtlas.Locales.each(fn l ->
        Paths.rating(l, SyliAtlas.Locales.pick(entry["slug"], l))
      end)

    history = Ratings.history(entry["code"])
    faq = RatingComponents.faq_items(name, entry, doc) ++ more_faq(name, entry, history, locale)
    description = description(entry, name)
    context = SyliAtlasWeb.CountryContext.get(entry["code"], locale)
    same_band = same_band(doc, entry, locale)
    communities = SyliAtlas.Economy.Communities.for_country(entry["code"])

    render(conn, :show,
      page_title: title(entry, name),
      seo:
        Seo.page(locale, paths, description, %{
          # A country without any rating has nothing to say beyond the main page.
          noindex: is_nil(entry["band"]),
          json_ld: [
            Seo.breadcrumbs([
              {"Syli Atlas", Paths.home(locale)},
              {gettext("Sovereign ratings"), Paths.ratings(locale)},
              {name, paths[locale]}
            ]),
            Seo.faq(faq)
          ]
        }),
      alternates: Seo.alternates_for_header(paths),
      doc: doc,
      entry: entry,
      name: name,
      history: history,
      faq: faq,
      context: context,
      same_band: same_band,
      communities: communities
    )
  end

  # Other countries in the same band (« Critical rating »…), best first.
  defp same_band(_doc, %{"band" => nil}, _locale), do: []

  defp same_band(doc, entry, locale) do
    for code <- doc["ranking"],
        code != entry["code"],
        e = doc["countries"][code],
        e["band"] == entry["band"] do
      %{
        name: SyliAtlas.Locales.pick(e["name"], locale),
        slug: SyliAtlas.Locales.pick(e["slug"], locale),
        label: e["label"]
      }
    end
  end

  # The latest decision, and the gap to investment grade, as questions.
  defp more_faq(_name, %{"band" => nil}, _history, _locale), do: []

  defp more_faq(name, entry, history, locale) do
    latest =
      case Enum.find(history, &(&1.action_date not in [nil, ""])) do
        nil ->
          []

        r ->
          [
            {gettext("When did the rating of %{name} last change?", name: name),
             gettext("%{agency}, %{date}: %{decision}, %{rating}, %{outlook}.",
               agency: RatingComponents.agency_name(r.agency),
               date: RatingComponents.date_text(r.action_date, locale),
               decision: String.downcase(RatingComponents.action_label(r.action_type)),
               rating: SyliAtlas.Ratings.Scale.display(r.rating),
               outlook: RatingComponents.outlook_label(r.outlook)
             )}
          ]
      end

    gap =
      if is_integer(entry["notches"]) and entry["notches"] > 0 do
        [
          {gettext("How far is %{name} from investment grade?", name: name),
           RatingComponents.gap_text(entry) <> "."}
        ]
      else
        []
      end

    latest ++ gap
  end

  # « Note souveraine du Sénégal : S&P CC, Moody's Ca »: the ratings
  # themselves are what people look for.
  defp title(%{"band" => nil}, name),
    do: gettext("Credit rating of %{name}: not rated by S&P, Moody's or Fitch", names(name))

  defp title(entry, name),
    do:
      gettext(
        "Credit rating of %{name}: %{agencies}",
        names(name,
          agencies: entry |> RatingComponents.agencies_text() |> String.replace(" · ", ", ")
        )
      )

  defp description(%{"band" => nil}, name),
    do: gettext("%{name} is not rated by S&P, Moody's or Fitch.", names(name))

  defp description(entry, name) do
    gettext("%{name}: %{agencies}. %{verdict}, %{category}, %{gap}.",
      name: name,
      agencies: RatingComponents.agencies_text(entry),
      verdict: RatingComponents.verdict(entry["band"]),
      category: String.downcase(RatingComponents.category(entry["band"])),
      gap: RatingComponents.gap_text(entry)
    )
  end

  defp empty,
    do: %{
      "countries" => %{},
      "ranking" => [],
      "unrated" => [],
      "counts" => %{},
      "rated" => 0,
      "recent" => [],
      "as_of" => nil
    }

  defp search(rows, "", _locale), do: rows

  defp search(rows, q, locale) do
    needle = Area.normalize(q)

    Enum.filter(rows, fn e ->
      String.contains?(Area.normalize(SyliAtlas.Locales.pick(e["name"], locale)), needle) or
        Enum.any?(e["agencies"], &(String.downcase(&1["rating"]) == String.downcase(q))) or
        String.downcase(e["label"] || "") == String.downcase(String.replace(q, "-", "−"))
    end)
  end

  @doc false
  def answer(%{"rated" => 0}, _locale),
    do: gettext("Credit ratings of African countries by S&P, Moody's and Fitch.")

  def answer(doc, locale) do
    investment = names(doc, &(&1["band"] == "investment"), locale)
    defaulted = names(doc, &(&1["band"] == "default"), locale)

    gettext(
      "%{rated} of the 54 African countries are rated by at least one of the three main agencies. Investment grade on average: %{investment}. Most rated countries are in the B category, « highly speculative ». In default or close to it: %{default}.",
      rated: doc["rated"],
      investment: list_or_none(investment),
      default: list_or_none(defaulted)
    )
  end

  defp names(doc, fun, locale) do
    doc["ranking"]
    |> Enum.map(&doc["countries"][&1])
    |> Enum.filter(fun)
    |> Enum.map(&"#{SyliAtlas.Locales.pick(&1["name"], locale)} (#{&1["label"]})")
  end

  defp list_or_none([]), do: gettext("none")
  defp list_or_none(list), do: Enum.join(list, ", ")

  defp faq(%{"rated" => 0}, _locale), do: []

  defp faq(doc, locale) do
    [best | _] = Enum.map(doc["ranking"], &doc["countries"][&1])
    investment = names(doc, &(&1["band"] == "investment"), locale)

    [
      {gettext("Which African country has the best credit rating?"),
       gettext("%{name}: %{agencies} (average %{rating} on the common scale).",
         name: SyliAtlas.Locales.pick(best["name"], locale),
         agencies: RatingComponents.agencies_text(best),
         rating: best["label"]
       )},
      {gettext("How many African countries are investment grade?"),
       gettext("%{count} on average of the agencies: %{names}.",
         count: length(investment),
         names: list_or_none(investment)
       )},
      {gettext("What does « speculative grade » mean?"),
       gettext(
         "A rating below BBB− (S&P, Fitch) or Baa3 (Moody's). The country remains solvent, but the agencies judge the risk higher: it borrows at a higher cost, and many pension funds cannot buy its debt."
       )},
      {gettext("Why do some countries have no rating?"),
       gettext(
         "They do not borrow on international markets or have not asked for a rating. Not being rated is not a bad rating."
       )}
    ]
  end

  defp dataset(doc, path) do
    %{
      "@context" => "https://schema.org",
      "@type" => "Dataset",
      "name" => gettext("Sovereign credit ratings of African countries"),
      "description" =>
        Seo.dataset_description(
          gettext(
            "Long-term foreign-currency ratings by S&P, Moody's and Fitch, latest decision of each agency."
          )
        ),
      "spatialCoverage" => "Africa",
      "dateModified" => doc["as_of"],
      "isBasedOn" => "S&P Global Ratings, Moody's Ratings, Fitch Ratings",
      "url" => Seo.url(path),
      "creator" => Seo.organization(),
      "publisher" => Seo.organization(),
      "isAccessibleForFree" => true,
      # The ratings are the agencies': cited, not relicensed. The terms are
      # set out, source by source, on the method page.
      "license" => %{
        "@type" => "CreativeWork",
        "name" => gettext("Sources and terms of use"),
        "url" => Seo.url(Paths.method(Gettext.get_locale(SyliAtlasWeb.Gettext)))
      }
    }
  end
end
