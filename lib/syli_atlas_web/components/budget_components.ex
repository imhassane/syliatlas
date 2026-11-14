defmodule SyliAtlasWeb.BudgetComponents do
  @moduledoc """
  The state budget of a country (its profile's « Budget » tab) and the
  pieces the budgets page shares with it: amounts in the reader's currency
  with the local amount under them, the laws one by one, their timeline,
  who votes the budget. Every figure names its source.

  Amounts are written server side in the default currency of the language
  (euro in French, dollar elsewhere); `assets/js/ui/money.js` rewrites them
  in the currency the reader picks (kept in the browser), from the rates
  embedded in the page. The page stays cacheable: nothing depends on the
  reader on the server.
  """
  use Phoenix.Component
  use Gettext, backend: SyliAtlasWeb.Gettext

  import SyliAtlasWeb.UI
  import SyliAtlasWeb.Format, only: [number: 3, names: 1, names: 2]

  alias SyliAtlas.Budgets.Money
  alias SyliAtlas.Economy.Currencies
  alias SyliAtlasWeb.Paths

  # Amounts ------------------------------------------------------------------

  attr :amount, :any, required: true, doc: "string (exact decimal) or number, in `currency`"
  attr :currency, :string, required: true
  attr :fx, :map, default: nil, doc: "the exchange rates document"
  attr :locale, :string, required: true
  attr :class, :any, default: nil

  @doc """
  An amount in the reader's currency, the local amount under it. Without
  rates, only the local amount.
  """
  def money(assigns) do
    amount = to_float(assigns.amount)
    shown = Money.default_currency(assigns.locale)
    converted = Money.convert(amount, assigns.currency, shown, assigns.fx)

    assigns =
      assign(assigns,
        value: amount,
        shown: shown,
        converted: converted,
        same?: shown == assigns.currency or is_nil(converted)
      )

    ~H"""
    <span :if={is_nil(@value)} class={["money", @class]}>—</span>
    <span
      :if={@value}
      class={["money", @class]}
      data-money={@value}
      data-currency={@currency}
    >
      <span class="money-main" data-money-main>{if(@same?,
        do: Money.short(@value, @currency, @locale),
        else: Money.short(@converted, @shown, @locale)
      )}</span>
      <span class="money-local" data-money-local hidden={@same?}>{Money.short(
        @value,
        @currency,
        @locale
      )}</span>
    </span>
    """
  end

  defp to_float(nil), do: nil
  defp to_float(v) when is_number(v), do: v * 1.0
  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(s) when is_binary(s), do: s |> Decimal.new() |> Decimal.to_float()

  attr :fx, :map, default: nil
  attr :locale, :string, required: true
  attr :local, :string, default: nil, doc: "the country's currency, offered first"
  attr :id, :string, default: "money-picker"

  @doc """
  « Show amounts in »: a list of currencies, hidden until the script runs
  (without it, amounts stay in the default currency, the local one under
  them). Carries the rates, units per US dollar.
  """
  def currency_picker(assigns) do
    rates = (assigns.fx && assigns.fx["rates"]) || %{}
    default = Money.default_currency(assigns.locale)

    codes =
      ([default, "USD", "EUR", assigns.local] ++ ["CNY"] ++ Currencies.codes())
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.filter(&(&1 == "USD" or Map.has_key?(rates, &1)))

    assigns =
      assign(assigns,
        codes: codes,
        default: default,
        rates_json: Jason.encode!(%{"rates" => rates, "date" => assigns.fx && assigns.fx["date"]})
      )

    ~H"""
    <div :if={@fx} class="money-picker" data-money-picker hidden>
      <label for={@id} class="small muted">{gettext("Show amounts in")}</label>
      <select id={@id} class="select select-sm" data-default={@default} data-locale={@locale}>
        <option :for={c <- @codes} value={c} selected={c == @default}>
          {currency_label(
            c,
            @locale
          )}
        </option>
      </select>
      <script type="application/json" data-money-rates>
        <%= Phoenix.HTML.raw(@rates_json) %>
      </script>
    </div>
    """
  end

  defp currency_label("USD", _locale), do: "USD · " <> gettext("US dollar")
  defp currency_label("EUR", _locale), do: "EUR · " <> gettext("euro")
  defp currency_label("CNY", _locale), do: "CNY · " <> gettext("yuan")

  defp currency_label(code, locale) do
    case Currencies.name_of(code, locale) do
      nil -> code
      name -> code <> " · " <> name
    end
  end

  # Labels ------------------------------------------------------------------

  def kind_label("initial"), do: gettext("Initial finance law")
  def kind_label("amending"), do: gettext("Amending finance law")
  def kind_label("settlement"), do: gettext("Settlement law")
  def kind_label("provisional"), do: gettext("Provisional budget")
  def kind_label(_), do: gettext("Budget law")

  @doc "The law in a few words, for a table cell: « Rectificative 2026 »."
  def kind_short(%{"kind" => kind, "fiscal_year" => year}) do
    label =
      case kind do
        "initial" -> gettext("Initial")
        "amending" -> gettext("Amending")
        "settlement" -> gettext("Settlement")
        _ -> gettext("Provisional")
      end

    "#{label} #{year}"
  end

  @doc "Who votes the budget, in a word or two."
  def legislature_kind_label("transition"), do: gettext("Transitional body")
  def legislature_kind_label("none"), do: gettext("No parliament")
  def legislature_kind_label("suspended"), do: gettext("Parliament not sitting")
  def legislature_kind_label(_), do: gettext("Parliament")

  @doc "The law's name with its year: « Loi de finances initiale 2026 »."
  def law_name(%{"kind" => kind, "fiscal_year" => year} = law) do
    seq =
      if kind == "amending" and (law["sequence"] || 1) > 1, do: " (#{law["sequence"]})", else: ""

    "#{kind_label(kind)} #{year}#{seq}"
  end

  def stage_label("tabled"), do: gettext("Tabled")
  def stage_label("voted"), do: gettext("Voted")
  def stage_label("promulgated"), do: gettext("Promulgated")
  def stage_label("published"), do: gettext("In the official gazette")
  def stage_label(_), do: "—"

  def stage_class("tabled"), do: "pill-warn"
  def stage_class("voted"), do: "pill-info"
  def stage_class(_), do: "pill-ok"

  def level_label("official"), do: gettext("Official budget law")
  def level_label(_), do: gettext("IMF estimate")

  def level_class("official"), do: "pill-ok"
  def level_class(_), do: "pill-neutral"

  def legislature_note("transition"),
    do:
      gettext("A transitional body votes the laws: the constitution's parliament is not sitting.")

  def legislature_note("none"),
    do: gettext("No legislature votes the budget: it is adopted by the executive.")

  def legislature_note("suspended"),
    do: gettext("The legislature has not sat for years: the budget is not voted.")

  def legislature_note(_), do: nil

  @doc "A date written as the site writes it, or nil."
  def date_text(nil, _locale), do: nil
  def date_text(iso, locale), do: SyliAtlasWeb.RatingComponents.date_text(iso, locale)

  # Pieces --------------------------------------------------------------------

  attr :level, :string, required: true

  def level_pill(assigns) do
    ~H"""
    <span class={["pill", level_class(@level)]} data-budget-level={@level}>{level_label(@level)}</span>
    """
  end

  attr :laws, :list, required: true
  attr :fx, :map, default: nil
  attr :locale, :string, required: true
  attr :id, :string, default: "budget-laws"

  @doc "The laws one by one: the latest year first."
  def law_table(assigns) do
    ~H"""
    <div class="table-box">
      <table class="table table-stack" id={@id}>
        <caption class="vh">{gettext("Budget laws, one by one")}</caption>
        <thead>
          <tr>
            <th scope="col" class="l">{gettext("Law")}</th>
            <th scope="col">{gettext("Revenue")}</th>
            <th scope="col">{gettext("Expenditure")}</th>
            <th scope="col" class="l">{gettext("Stage")}</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={l <- @laws} id={"law-#{l["id"]}"}>
            <th scope="row" class="l">
              <span class="law-name">{law_name(l)}</span>
              <span :if={l["reference"]} class="small subtle law-ref">{l["reference"]}</span>
              <a href={l["source_url"]} rel="noopener" class="small law-src">
                {l["source_name"]}<span class="vh"> ({gettext("official text, opens the source")})</span>
              </a>
            </th>
            <td data-label={gettext("Revenue")}>
              <.money amount={l["revenue"]} currency={l["currency"]} fx={@fx} locale={@locale} />
            </td>
            <td data-label={gettext("Expenditure")}>
              <.money amount={l["expenditure"]} currency={l["currency"]} fx={@fx} locale={@locale} />
            </td>
            <td data-label={gettext("Stage")} class="l">
              <span class={["pill", stage_class(l["stage"])]}>{stage_label(l["stage"])}</span>
              <time :if={l["last_date"]} datetime={l["last_date"]} class="small subtle law-date">
                {date_text(l["last_date"], @locale)}
              </time>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :laws, :list, required: true
  attr :locale, :string, required: true

  @doc "Every step of every law, latest first: tabled, voted, promulgated, published."
  def law_timeline(assigns) do
    assigns = assign(assigns, :events, timeline(assigns.laws))

    ~H"""
    <ol class="timeline" id="budget-timeline">
      <li :for={e <- @events} class={["timeline-item", "timeline-" <> e.step]}>
        <span class="timeline-dot" aria-hidden="true"></span>
        <time datetime={e.date} class="timeline-date">{date_text(e.date, @locale)}</time>
        <p class="timeline-title">{law_name(e.law)} · {step_label(e.step)}</p>
        <p :if={e.step == "voted" and e.law["legislature"]} class="small muted">
          {e.law["legislature"]}{votes(e.law)}
        </p>
      </li>
    </ol>
    """
  end

  defp timeline(laws) do
    for l <- laws,
        {step, key} <- [
          {"tabled", "tabled_on"},
          {"voted", "voted_on"},
          {"promulgated", "promulgated_on"},
          {"published", "published_on"}
        ],
        date = l[key],
        date != nil do
      %{law: l, step: step, date: date}
    end
    |> Enum.sort_by(&{&1.date, step_rank(&1.step)}, :desc)
  end

  defp step_rank("tabled"), do: 0
  defp step_rank("voted"), do: 1
  defp step_rank("promulgated"), do: 2
  defp step_rank("published"), do: 3

  defp step_label("tabled"), do: gettext("tabled")
  defp step_label("voted"), do: gettext("voted")
  defp step_label("promulgated"), do: gettext("promulgated")
  defp step_label("published"), do: gettext("published in the official gazette")

  defp votes(%{"votes_for" => f, "votes_against" => a}) when is_integer(f) and is_integer(a),
    do: " · " <> gettext("%{for} for, %{against} against", for: f, against: a)

  defp votes(%{"votes_for" => f}) when is_integer(f),
    do: " · " <> gettext("%{for} votes for", for: f)

  defp votes(_), do: ""

  # The tab of a country profile -----------------------------------------------

  attr :doc, :map, required: true, doc: "the country's budget document"
  attr :name, :string, required: true
  attr :fx, :map, default: nil
  attr :locale, :string, required: true
  attr :year, :integer, required: true

  @doc "The « Budget » tab of a country profile."
  def country_budget(assigns) do
    doc = assigns.doc
    laws = doc["laws"]
    budget_laws = Enum.filter(laws, &(&1["kind"] in ["initial", "amending"]))
    current = List.first(budget_laws)
    year = (current && current["fiscal_year"]) || assigns.year
    imf_rev = get_in(doc, ["imf", "revenue", Integer.to_string(year)])
    imf_exp = get_in(doc, ["imf", "expenditure", Integer.to_string(year)])

    assigns =
      assign(assigns,
        laws: laws,
        current: current,
        shown_year: year,
        imf_rev: imf_rev,
        imf_exp: imf_exp,
        profile: doc["profile"] || %{},
        imf_years: imf_years(doc, assigns.year)
      )

    ~H"""
    <.section id="budget">
      <.section_head
        eyebrow={gettext("State budget · %{year}", year: @shown_year)}
        title={budget_title(@current, @imf_exp, @name, @shown_year, @fx, @locale)}
      >
        <:intro>{budget_lead(@current, @imf_rev, @imf_exp, @name, @shown_year, @locale)}</:intro>
        <:actions>
          <div class="budget-actions">
            <.level_pill level={@doc["level"]} />
            <.currency_picker
              :if={@laws != []}
              fx={@fx}
              locale={@locale}
              local={@doc["currency"]}
            />
          </div>
        </:actions>
      </.section_head>

      <dl :if={@current} class="stats stats-3">
        <div>
          <dt>{gettext("Revenue")}</dt>
          <dd class="big" data-kpi="budget-revenue">
            <.money
              amount={@current["revenue"]}
              currency={@current["currency"]}
              fx={@fx}
              locale={@locale}
            />
          </dd>
          <dd class="small muted">{law_name(@current)}</dd>
        </div>
        <div>
          <dt>{gettext("Expenditure")}</dt>
          <dd class="big" data-kpi="budget-expenditure">
            <.money
              amount={@current["expenditure"]}
              currency={@current["currency"]}
              fx={@fx}
              locale={@locale}
            />
          </dd>
          <dd class="small muted">{stage_label(@current["stage"])}</dd>
        </div>
        <div>
          <dt>{gettext("Revenue minus expenditure")}</dt>
          <dd class="big" data-kpi="budget-balance">
            <.money
              amount={difference(@current)}
              currency={@current["currency"]}
              fx={@fx}
              locale={@locale}
            />
          </dd>
          <dd class="small muted">{gettext("Syli Atlas calculation, from the law")}</dd>
        </div>
      </dl>

      <.stat_grid :if={!@current} class="stats-3">
        <:stat
          id="budget-revenue"
          label={gettext("Revenue · %{year}", year: @shown_year)}
          value={pct(@imf_rev, @locale)}
        >
          {gettext("of GDP · IMF estimate")}
        </:stat>
        <:stat
          id="budget-expenditure"
          label={gettext("Expenditure · %{year}", year: @shown_year)}
          value={pct(@imf_exp, @locale)}
        >
          {gettext("of GDP · IMF estimate")}
        </:stat>
        <:stat
          id="budget-balance"
          label={gettext("Balance · %{year}", year: @shown_year)}
          value={pct(diff(@imf_rev, @imf_exp), @locale)}
        >
          {gettext("of GDP · revenue minus expenditure")}
        </:stat>
      </.stat_grid>

      <div class="grid grid-2 budget-grid">
        <.card :if={@laws != []} pad class="budget-laws-card">
          <.card_head
            title={gettext("Budget laws, one by one")}
            subtitle={gettext("Each figure checked against the official text, linked under the law")}
          />
          <.law_table laws={@laws} fx={@fx} locale={@locale} />
        </.card>

        <.card :if={@laws == []} pad class="budget-empty" id="budget-empty">
          <.card_head
            title={gettext("No budget law collected yet")}
            subtitle={gettext("The figures above are the IMF's, for the whole general government")}
          />
          <p>
            {gettext(
              "Syli Atlas adds each country's finance laws as they are published, checked by hand against the official text. Until then, this page shows the IMF's estimate."
            )}
          </p>
          <p :if={@profile["gazette_url"]} class="small">
            <a href={@profile["gazette_url"]} rel="noopener">{@profile["gazette_name"]}</a>
          </p>
        </.card>

        <.card pad id="budget-who">
          <.card_head title={gettext("Who votes the budget")} />
          <dl class="budget-facts">
            <div>
              <dt>{gettext("Legislature")}</dt>
              <dd>{legislature(@profile, @locale) || "—"}</dd>
            </div>
            <div :if={@profile["gazette_name"]}>
              <dt>{gettext("Laws published in")}</dt>
              <dd>
                <a :if={@profile["gazette_url"]} href={@profile["gazette_url"]} rel="noopener">{@profile[
                  "gazette_name"
                ]}</a>
                <span :if={!@profile["gazette_url"]}>{@profile["gazette_name"]}</span>
              </dd>
            </div>
            <div :if={@profile["finance_url"]}>
              <dt>{gettext("Ministry of Finance")}</dt>
              <dd>
                <a href={@profile["finance_url"]} rel="noopener">{host(@profile["finance_url"])}</a>
              </dd>
            </div>
          </dl>
          <p :if={legislature_note(@profile["kind"])} class="small muted">
            {legislature_note(@profile["kind"])}
          </p>
        </.card>

        <.card :if={@laws != []} pad id="budget-chronology">
          <.card_head
            title={gettext("Timeline")}
            subtitle={gettext("Tabled, voted, promulgated, published")}
          />
          <.law_timeline laws={@laws} locale={@locale} />
        </.card>

        <.card pad id="budget-imf">
          <.card_head
            title={gettext("Revenue and expenditure, % of GDP")}
            subtitle={gettext("IMF, general government · italics: estimates and projections")}
          />
          <div class="table-box">
            <table class="table" id="budget-imf-table">
              <caption class="vh">
                {gettext("Revenue and expenditure of %{name}, % of GDP (IMF)", names(@name))}
              </caption>
              <thead>
                <tr>
                  <th scope="col" class="l">{gettext("Year")}</th>
                  <th scope="col">{gettext("Revenue")}</th>
                  <th scope="col">{gettext("Expenditure")}</th>
                  <th scope="col">{gettext("Balance")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={r <- @imf_years} class={r.projection && "est"}>
                  <th scope="row" class="l">{r.year}</th>
                  <td class="num">{pct(r.revenue, @locale)}</td>
                  <td class="num">{pct(r.expenditure, @locale)}</td>
                  <td class={["num", (is_number(r.balance) and r.balance < 0) && "down"]}>
                    {pct(
                      r.balance,
                      @locale
                    )}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </.card>
      </div>

      <div class="stack gap-1">
        <p class="src">
          {gettext(
            "Budget laws: official texts, read by Syli Atlas (AI-assisted reading, every figure checked by hand before publication) · amounts in the law's currency, converted at the day's rate (Syli Atlas, docs: currencies)"
          )}
        </p>
        <p class="src">
          {gettext("Revenue and expenditure in % of GDP: %{source}, general government",
            source: "IMF, " <> (@doc["imf"]["label"] || "Fiscal Monitor")
          )} · <a href={@doc["imf"]["url"]} rel="noopener">imf.org</a>
        </p>
        <p class="src">
          <a href={Paths.budgets(@locale)}>{gettext("Budgets of the 54 countries")} →</a>
        </p>
      </div>
    </.section>
    """
  end

  defp difference(%{"revenue" => r, "expenditure" => e}) when is_binary(r) and is_binary(e),
    do: Decimal.sub(Decimal.new(r), Decimal.new(e)) |> Decimal.to_string(:normal)

  defp difference(_), do: nil

  defp diff(r, e) when is_number(r) and is_number(e), do: r - e
  defp diff(_, _), do: nil

  def pct(nil, _locale), do: "—"
  def pct(v, locale), do: number(v, 1, locale) <> " %"

  defp imf_years(doc, year) do
    for y <- (year - 5)..(year + 1) do
      r = get_in(doc, ["imf", "revenue", Integer.to_string(y)])
      e = get_in(doc, ["imf", "expenditure", Integer.to_string(y)])
      %{year: y, revenue: r, expenditure: e, balance: diff(r, e), projection: y >= year}
    end
  end

  def legislature(%{"legislature" => l}, locale) when is_map(l),
    do: if(locale == "fr", do: l["fr"], else: l["en"] || l["fr"])

  def legislature(_, _), do: nil

  defp host(url), do: URI.parse(url).host

  @doc "The heading of the budget tab."
  def budget_title(nil, exp, name, year, _fx, locale) when is_number(exp),
    do:
      gettext(
        "%{name}: public spending at %{pct} of GDP in %{year}",
        names(name, pct: pct(exp, locale), year: year)
      )

  def budget_title(nil, _exp, name, _year, _fx, _locale),
    do: gettext("State budget of %{name}", names(name))

  def budget_title(law, _exp, name, year, fx, locale) do
    shown = Money.default_currency(locale)
    value = Money.convert(to_float(law["expenditure"]), law["currency"], shown, fx)

    if value do
      gettext(
        "%{name}: %{amount} of expenditure authorised for %{year}",
        names(name, amount: Money.short(value, shown, locale), year: year)
      )
    else
      gettext("State budget of %{name}", names(name))
    end
  end

  @doc "The lead sentence of the budget tab, citable as such."
  def budget_lead(nil, rev, exp, name, year, locale) when is_number(rev) and is_number(exp) do
    gettext(
      "In %{year}, the IMF estimates the revenue of %{name}'s public administrations at %{rev} of GDP and their expenditure at %{exp}. No finance law of %{name} is on Syli Atlas yet.",
      names(name, year: year, rev: pct(rev, locale), exp: pct(exp, locale))
    )
  end

  def budget_lead(nil, _rev, _exp, name, _year, _locale),
    do: gettext("The IMF publishes no budget figures for %{name}.", names(name))

  def budget_lead(law, _rev, _exp, name, _year, locale) do
    gettext(
      "%{law} of %{name} authorises %{exp} of expenditure for %{rev} of revenue (%{stage}, official text linked below).",
      names(name,
        law: law_name(law),
        exp: Money.short(to_float(law["expenditure"]), law["currency"], locale),
        rev: Money.short(to_float(law["revenue"]), law["currency"], locale),
        stage: String.downcase(stage_label(law["stage"]))
      )
    )
  end
end
