defmodule SyliAtlasWeb.RatingsController do
  use SyliAtlasWeb, :controller

  alias SyliAtlas.Geo.Area
  alias SyliAtlas.Ratings
  alias SyliAtlas.Ratings.Scale
  alias SyliAtlasWeb.{Paths, RatingComponents, Seo}

  plug :put_layout, false

  @tabs Scale.bands() ++ ["unrated"]

  @doc "The 54 countries and their ratings, filtered by verdict or searched by name or rating."
  def index(conn, params) do
    locale = conn.assigns.locale
    paths = %{"fr" => Paths.ratings("fr"), "en" => Paths.ratings("en")}
    doc = Ratings.document() || empty()
    verdict = if params["verdict"] in @tabs, do: params["verdict"]
    q = params |> Map.get("q", "") |> String.trim() |> String.slice(0, 60)

    ranked =
      doc["ranking"]
      |> Enum.map(&doc["countries"][&1])

    unrated =
      doc["unrated"]
      |> Enum.map(&doc["countries"][&1])
      |> Enum.sort_by(&Area.normalize(&1["name"][locale]))

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
      String.contains?(Area.normalize(e["name"][locale]), needle) or
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
    |> Enum.map(&"#{&1["name"][locale]} (#{&1["label"]})")
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
         name: best["name"][locale],
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
        gettext(
          "Long-term foreign-currency ratings by S&P, Moody's and Fitch, latest decision of each agency."
        ),
      "spatialCoverage" => "Africa",
      "dateModified" => doc["as_of"],
      "isBasedOn" => "S&P Global Ratings, Moody's Ratings, Fitch Ratings",
      "url" => Seo.url(path)
    }
  end
end
