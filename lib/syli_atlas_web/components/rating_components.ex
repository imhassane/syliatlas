defmodule SyliAtlasWeb.RatingComponents do
  @moduledoc """
  Sovereign credit ratings on the pages: the verdict pill, the country
  section, the scale gauge and the home section.

  The verdict (« Fair rating ») is Syli Atlas's plain reading of the band
  an average falls in (`SyliAtlas.Ratings.Scale`); every place that shows
  it also shows the agencies' own ratings and says so.
  """
  use Phoenix.Component
  use Gettext, backend: SyliAtlasWeb.Gettext

  alias SyliAtlas.Ratings.Scale
  alias SyliAtlasWeb.Paths
  import SyliAtlasWeb.Format, only: [names: 1, names: 2]

  # Words ----------------------------------------------------------------

  def band_class(nil), do: "rt-none"
  def band_class("investment"), do: "rt-inv"
  def band_class("speculative"), do: "rt-spec"
  def band_class("highly_speculative"), do: "rt-high"
  def band_class("substantial_risk"), do: "rt-risk"
  def band_class("default"), do: "rt-def"

  @doc "The plain verdict: good, fair, weak…"
  def verdict(nil), do: gettext("No agency rating")
  def verdict("investment"), do: gettext("Good rating")
  def verdict("speculative"), do: gettext("Fair rating")
  def verdict("highly_speculative"), do: gettext("Weak rating")
  def verdict("substantial_risk"), do: gettext("Very weak rating")
  def verdict("default"), do: gettext("Critical rating")

  @doc "The agencies' category."
  def category(nil), do: gettext("Not rated")
  def category("investment"), do: gettext("Investment grade")
  def category("speculative"), do: gettext("Speculative (BB)")
  def category("highly_speculative"), do: gettext("Highly speculative (B)")
  def category("substantial_risk"), do: gettext("Substantial risk (CCC)")
  def category("default"), do: gettext("Default or near default")

  @doc "What the band means for the country's borrowing."
  def meaning(nil),
    do:
      gettext(
        "None of the three main agencies rates this country. Not being rated is not a bad rating."
      )

  def meaning("investment"),
    do:
      gettext(
        "The agencies judge the risk of default low. The country can borrow from the large pension and insurance funds, at lower rates."
      )

  def meaning("speculative"),
    do:
      gettext(
        "Not yet investment grade, but at the top of the speculative grade: the country borrows on the markets, at a higher cost than an investment-grade one."
      )

  def meaning("highly_speculative"),
    do:
      gettext(
        "The country pays its debts, but a shock (commodity prices, a political crisis) could stop it. Borrowing is expensive."
      )

  def meaning("substantial_risk"),
    do:
      gettext(
        "The agencies see a real risk of default; access to international markets is very difficult."
      )

  def meaning("default"),
    do:
      gettext(
        "A default is under way or judged very likely: a debt restructuring with losses for creditors is expected."
      )

  def agency_name("sp"), do: "S&P"
  def agency_name("moodys"), do: "Moody's"
  def agency_name("fitch"), do: "Fitch"
  def agency_name("afcra"), do: "AfCRA"

  def outlook_label("positive"), do: gettext("positive outlook")
  def outlook_label("negative"), do: gettext("negative outlook")
  def outlook_label("stable"), do: gettext("stable outlook")
  def outlook_label("developing"), do: gettext("developing outlook")
  def outlook_label("none"), do: gettext("no outlook")
  def outlook_label(_), do: gettext("outlook to check")

  def trend_label("up"), do: gettext("Rising")
  def trend_label("down"), do: gettext("Falling")
  def trend_label(_), do: gettext("Stable")

  def trend_class("up"), do: "up"
  def trend_class("down"), do: "down"
  def trend_class(_), do: nil

  def action_label("upgrade"), do: gettext("upgraded")
  def action_label("downgrade"), do: gettext("downgraded")
  def action_label("default"), do: gettext("default")
  def action_label("outlook_up"), do: gettext("outlook raised")
  def action_label("outlook_down"), do: gettext("outlook lowered")
  def action_label(_), do: gettext("affirmed")

  @doc "« no. 5 of 34 in Africa »."
  def rank_text(%{"rank" => rank}, rated) when is_integer(rank),
    do: gettext("no. %{rank} of %{of} in Africa", rank: rank, of: rated)

  def rank_text(_entry, _rated), do: nil

  @doc "Where the rank puts the country in a sentence."
  def tier_text(rank) when is_integer(rank) and rank <= 8,
    do: gettext("among the best rated in Africa")

  def tier_text(rank) when is_integer(rank) and rank <= 22,
    do: gettext("in the middle of the African ranking")

  def tier_text(_rank), do: gettext("among the lowest rated in Africa")

  @doc "Notches to or above the investment grade."
  def gap_text(%{"notches" => n}) when is_integer(n) and n > 0,
    do:
      ngettext(
        "%{count} notch below investment grade",
        "%{count} notches below investment grade",
        n
      )

  def gap_text(%{"notches" => 0}), do: gettext("right at the investment grade threshold")

  def gap_text(%{"notches" => n}) when is_integer(n),
    do:
      ngettext(
        "%{count} notch above the investment grade threshold",
        "%{count} notches above the investment grade threshold",
        -n
      )

  def gap_text(_entry), do: nil

  @doc "« S&P BB · Moody's Ba2 · Fitch BB »."
  def agencies_text(%{"agencies" => agencies}),
    do:
      Enum.map_join(
        agencies,
        " · ",
        &"#{agency_name(&1["agency"])} #{Scale.display(&1["rating"])}"
      )

  def agencies_text(_), do: ""

  @months_fr ~w(janv. févr. mars avr. mai juin juil. août sept. oct. nov. déc.)
  @months_en ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

  @doc "A full, month or year date: « 14 nov. 2025 », « oct. 2026 », « 2026 »."
  def date_text(nil, _locale), do: nil
  def date_text("", _locale), do: nil

  def date_text(iso, locale) do
    months = if locale == "en", do: @months_en, else: @months_fr

    case String.split(iso, "-") do
      [y, m, d] -> "#{String.to_integer(d)} #{Enum.at(months, String.to_integer(m) - 1)} #{y}"
      [y, m] -> "#{Enum.at(months, String.to_integer(m) - 1)} #{y}"
      [y] -> y
    end
  end

  def headline(%{"band" => nil}, _name), do: gettext("No agency rating")

  def headline(%{"band" => "investment"} = e, name),
    do: gettext("%{rating}: %{name} is investment grade", names(name, rating: e["label"]))

  def headline(%{"band" => "speculative"} = e, _name),
    do: gettext("%{rating}: a fair rating, %{gap}", rating: e["label"], gap: gap_text(e))

  def headline(%{"band" => "highly_speculative"} = e, _name),
    do: gettext("%{rating}: a weak rating, highly speculative", rating: e["label"])

  def headline(%{"band" => "substantial_risk"} = e, _name),
    do: gettext("%{rating}: a very weak rating", rating: e["label"])

  def headline(%{"band" => "default"} = e, _name),
    do: gettext("%{rating}: a critical rating, default judged likely", rating: e["label"])

  # Components -------------------------------------------------------------

  @doc "Question and answer on a country's rating, for the FAQ of its pages."
  def faq_items(_name, nil, _doc), do: []

  def faq_items(name, %{"band" => nil}, _doc) do
    [
      {gettext("What is the credit rating of %{name}?", names(name)),
       gettext("%{name} is not rated by S&P, Moody's or Fitch.", names(name))}
    ]
  end

  def faq_items(name, rating, doc) do
    [
      {gettext("What is the credit rating of %{name}?", names(name)),
       gettext("%{agencies}: %{verdict}, %{category}, %{gap}, %{rank}.",
         agencies: agencies_text(rating),
         verdict: String.downcase(verdict(rating["band"])),
         category: String.downcase(category(rating["band"])),
         gap: gap_text(rating),
         rank: rank_text(rating, doc["rated"])
       )}
    ]
  end

  attr :band, :string, default: nil
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def verdict_badge(assigns) do
    ~H"""
    <span class={["rt-badge", band_class(@band), @class]}>{render_slot(@inner_block)}</span>
    """
  end

  attr :entry, :map, required: true
  attr :rated, :integer, required: true
  attr :href, :string, required: true

  @doc "The compact summary under a country's title."
  def rating_pill(assigns) do
    ~H"""
    <a class="rt-pill card" href={@href} id="rating-pill">
      <span class="subtle small">{gettext("Sovereign rating")}</span>
      <b :if={@entry["label"]} class="num rt-pill-label">{@entry["label"]}</b>
      <.verdict_badge band={@entry["band"]}>
        {verdict(@entry["band"])}<span :if={@entry["band"]}> · {category(@entry["band"])}</span>
      </.verdict_badge>
      <span :if={@entry["band"]} class="small muted">
        {gap_text(@entry)} · {rank_text(@entry, @rated)}
      </span>
      <span class="rt-pill-more">{gettext("Details")} →</span>
    </a>
    """
  end

  attr :entry, :map, required: true
  attr :name, :string, required: true

  @doc "Where the average sits on the common scale, default to AAA."
  def scale_gauge(assigns) do
    left = if assigns.entry["average"], do: (assigns.entry["average"] - 1) / 21 * 100

    assigns = assign(assigns, left: left && Float.round(left, 1))

    ~H"""
    <div class="rt-gauge" role="img" aria-label={gauge_label(@entry, @name)}>
      <div :if={@left} class="rt-gauge-marker" style={"left: #{@left}%"}>
        <span>{@name} · {@entry["label"]}</span>
      </div>
      <div class="rt-gauge-bar" aria-hidden="true">
        <span class="rt-def"></span><span class="rt-risk"></span><span class="rt-high"></span><span class="rt-spec"></span><span class="rt-inv"></span>
      </div>
      <div class="rt-gauge-legend" aria-hidden="true">
        <span class="rt-def"><b>{gettext("Default")}</b> D–CC</span>
        <span class="rt-risk"><b>CCC</b></span>
        <span class="rt-high"><b>B</b></span>
        <span class="rt-spec"><b>BB</b></span>
        <span class="rt-inv"><b>{gettext("Investment grade")}</b> BBB−–AAA</span>
      </div>
    </div>
    """
  end

  defp gauge_label(%{"label" => nil}, name), do: gettext("%{name} is not rated", names(name))

  defp gauge_label(e, name),
    do:
      gettext("%{name}: average rating %{rating} on a scale from default to AAA, %{gap}",
        name: name,
        rating: e["label"],
        gap: gap_text(e)
      )

  attr :entry, :map, required: true
  attr :name, :string, required: true
  attr :rated, :integer, required: true
  attr :locale, :string, required: true

  attr :page, :boolean,
    default: false,
    doc: "on the country's ratings page: h1, link back to the profile"

  @doc "The full section of a country profile, or the top of the country's ratings page."
  def rating_section(assigns) do
    ~H"""
    <section class={["section", @page && "rt-page-top"]} id="notation">
      <div class="wrap stack gap-4">
        <div class="head-row">
          <div class="section-head">
            <p class="eyebrow">{gettext("Sovereign rating")}</p>
            <.dynamic_tag tag_name={if @page, do: "h1", else: "h2"} class="h1 rt-title">
              {if @page,
                do: gettext("Credit rating of %{name} · %{headline}", names(@name, headline: headline(@entry, @name))),
                else: headline(@entry, @name)}
            </.dynamic_tag>
            <p class="lead rt-lead">
              <%= if @entry["band"] do %>
                {gettext(
                  "%{name} is no. %{rank} of the %{of} African countries rated, %{tier}.",
                  names(@name, rank: @entry["rank"], of: @rated, tier: tier_text(@entry["rank"]))
                )}
                {meaning(@entry["band"])}
              <% else %>
                {meaning(nil)}
              <% end %>
            </p>
          </div>
          <div class="head-actions">
            <a
              :if={!@page and @entry["band"]}
              class="btn btn-secondary"
              id="rating-history-link"
              href={Paths.rating(@locale, @entry["slug"][@locale])}
            >
              {gettext("History of decisions")} →
            </a>
            <a
              :if={@page}
              class="btn btn-secondary"
              href={Paths.area(@locale, "country", @entry["slug"][@locale])}
            >
              {gettext("Profile of %{name}", name: @name)} →
            </a>
            <a class="btn btn-secondary" href={Paths.ratings(@locale)}>{gettext(
              "Ratings of the 54 countries"
            )} →</a>
          </div>
        </div>

        <div :if={@entry["band"]} class="card pad rt-verdict" id="rating-verdict">
          <div class="stack gap-2">
            <div class="row gap-2">
              <.verdict_badge band={@entry["band"]} class="rt-badge-lg">
                {verdict(@entry["band"])}
              </.verdict_badge>
              <span class="num rt-big">{@entry["label"]}</span>
            </div>
            <dl class="rt-facts">
              <div>
                <dt>{gettext("Category")}</dt>
                <dd class={band_class(@entry["band"])}>{category(@entry["band"])}</dd>
              </div>
              <div>
                <dt>{gettext("In Africa")}</dt>
                <dd>{gettext("no. %{rank} of %{of}", rank: @entry["rank"], of: @rated)}</dd>
              </div>
              <div>
                <dt>{gettext("Trend")}</dt>
                <dd class={trend_class(@entry["trend"])}>{trend_label(@entry["trend"])}</dd>
              </div>
            </dl>
          </div>
          <div class="stack gap-2 rt-verdict-scale">
            <.scale_gauge entry={@entry} name={@name} />
            <p class="small muted">{gap_text(@entry)}</p>
          </div>
        </div>

        <div :if={@entry["agencies"] != []} class="rt-agencies">
          <div :for={a <- @entry["agencies"]} class="card pad rt-agency">
            <p class="mono subtle caption">{agency_name(a["agency"])}</p>
            <p class="num rt-agency-rating">
              {Scale.display(a["rating"])}<span :if={a["needs_check"]} title={gettext("To check")}>*</span>
            </p>
            <p class="small muted">
              {outlook_label(a["outlook"])}
              <span :if={a["action_date"] not in [nil, ""]}>
                · {action_label(a["action_type"])} {date_text(a["action_date"], @locale)}
              </span>
            </p>
            <a :if={a["source_url"]} class="small" href={a["source_url"]} rel="nofollow noopener">{gettext(
              "Source"
            )} ↗</a>
          </div>
          <div class="card pad rt-agency rt-agency-empty">
            <p class="mono subtle caption">AfCRA</p>
            <p class="num rt-agency-rating subtle">—</p>
            <p class="small muted">
              {gettext(
                "The African agency, launched on 7 October 2026, has not published a rating yet."
              )}
            </p>
          </div>
        </div>
        <p class="src">
          {gettext(
            "Long-term foreign-currency ratings, from the agencies' releases · verdict and common scale: Syli Atlas's reading of the agencies' categories · a rating is an opinion on credit risk, not investment advice"
          )}
        </p>
      </div>
    </section>
    """
  end

  attr :doc, :map, required: true
  attr :locale, :string, required: true

  @doc "The home section: how the rated countries spread, the best rated, the latest changes."
  def home_ratings(assigns) do
    doc = assigns.doc

    assigns =
      assign(assigns,
        bands: Enum.map(Scale.bands(), &{&1, doc["counts"][&1] || 0}),
        top: doc["ranking"] |> Enum.take(5) |> Enum.map(&doc["countries"][&1]),
        recent: Enum.take(doc["recent"], 5)
      )

    ~H"""
    <section class="section" id="ratings">
      <div class="wrap stack gap-6">
        <div class="head-row">
          <div class="section-head">
            <p class="eyebrow">{gettext("Sovereign ratings · S&P, Moody's, Fitch")}</p>
            <h2 class="h1">{gettext("What the rating agencies think.")}</h2>
            <p class="lead">
              {gettext(
                "%{rated} countries are rated. Only %{investment} are investment grade on average; most are « highly speculative » (B).",
                rated: @doc["rated"],
                investment: @doc["counts"]["investment"]
              )}
            </p>
          </div>
          <div class="head-actions">
            <a class="btn btn-secondary" href={Paths.ratings(@locale)}>{gettext(
              "Ratings of the 54 countries"
            )} →</a>
          </div>
        </div>
        <div class="card pad stack gap-2">
          <div class="rt-spread" role="img" aria-label={spread_label(@bands, @doc["unrated"])}>
            <span
              :for={{band, n} <- @bands}
              :if={n > 0}
              class={band_class(band)}
              style={"flex: #{n}"}
            >{n}</span>
          </div>
          <ul class="rt-spread-legend">
            <li :for={{band, _n} <- @bands}>
              <b class={band_class(band)}>{verdict(band)}</b>
              <span class="muted">· {category(band)}</span>
            </li>
            <li class="subtle">
              {ngettext(
                "+ %{count} country without a rating",
                "+ %{count} countries without a rating",
                length(@doc["unrated"])
              )}
            </li>
          </ul>
        </div>
        <div class="grid">
          <div class="card qcard" id="ratings-top">
            <span class="eyebrow">{gettext("Best rated")}</span>
            <div>
              <div :for={{e, i} <- Enum.with_index(@top, 1)} class="list-row">
                <a href={Paths.area(@locale, "country", e["slug"][@locale])}>{i} · {e["name"][@locale]}</a>
                <span>
                  <b class="num">{e["label"]}</b>
                  <.verdict_badge band={e["band"]}>{category(e["band"])}</.verdict_badge>
                </span>
              </div>
            </div>
            <a href={Paths.ratings(@locale)} class="qcard-cta">{gettext(
              "See the %{count} rated countries",
              count: @doc["rated"]
            )} →</a>
          </div>
          <div class="card qcard" id="ratings-recent">
            <span class="eyebrow">{gettext("Latest changes")}</span>
            <div>
              <div :for={r <- @recent} class="list-row">
                <span>
                  {@doc["countries"][r["code"]]["name"][@locale]} · {agency_name(r["agency"])} · {date_text(
                    r["action_date"],
                    @locale
                  )}
                </span>
                <b class={[
                  "num",
                  r["action_type"] == "upgrade" && "up",
                  r["action_type"] != "upgrade" && "down"
                ]}>
                  {if(r["action_type"] == "upgrade", do: "▲", else: "▼")} {Scale.display(r["rating"])}
                </b>
              </div>
            </div>
          </div>
        </div>
        <p class="src">
          {gettext(
            "Long-term foreign-currency ratings · average on a common scale computed by Syli Atlas · sources: the agencies' releases · not investment advice"
          )}
        </p>
      </div>
    </section>
    """
  end

  defp spread_label(bands, unrated) do
    parts = Enum.map_join(bands, ", ", fn {b, n} -> "#{n} · #{category(b)}" end)

    gettext("Rated countries by category: %{parts}; %{unrated} without a rating",
      parts: parts,
      unrated: length(unrated)
    )
  end

  attr :entry, :map, default: nil

  @doc "A small badge with a country's average rating (chips, lists)."
  def rating_chip(assigns) do
    ~H"""
    <span :if={@entry && @entry["label"]} class={["rt-chip num", band_class(@entry["band"])]}>{@entry[
      "label"
    ]}</span>
    <span :if={@entry && @entry["band"] == nil} class="rt-chip rt-none">{gettext("not rated")}</span>
    """
  end
end
