defmodule SyliAtlasWeb.NationalComponents do
  @moduledoc """
  National figures next to the IMF's (SyliAtlas.National): the status
  badge, the rebasing notice, the double cards of a country, and the sum
  of national figures for Africa.
  """
  use Phoenix.Component
  use Gettext, backend: SyliAtlasWeb.Gettext

  alias SyliAtlas.National
  alias SyliAtlasWeb.{Format, Paths, PublicData}

  @doc "Label of a figure's status."
  def status_label("pending_review"), do: gettext("Being checked")
  def status_label("auto_verified"), do: gettext("Checked automatically")
  def status_label("verified"), do: gettext("Checked")
  def status_label(_), do: ""

  def status_class("pending_review"), do: "pill-warn"
  def status_class(_), do: "pill-ok"

  attr :figure, :map, required: true
  attr :id, :string, default: nil

  @doc "The badge of a figure being checked; a verified figure needs none."
  def status_badge(assigns) do
    ~H"""
    <span
      :if={@figure["status"] == "pending_review"}
      class={["pill", status_class(@figure["status"])]}
      id={@id}
    >
      {status_label(@figure["status"])}
    </span>
    """
  end

  attr :entry, :map, default: nil
  attr :locale, :string, required: true

  @doc "The notice of a change of base year, until an IMF edition catches up."
  def rebasing_notice(assigns) do
    assigns = assign(assigns, :r, assigns.entry && assigns.entry["rebasing"])

    ~H"""
    <div :if={@r && @r["active"]} class="card national-notice" role="note" id="national-rebasing">
      <span class="pill pill-warn">
        {gettext("GDP rebased, %{date}", date: day(@r["announced_on"], @locale))}
      </span>
      <p>
        {gettext(
          "The national accounts have a new base year (%{new} instead of %{old}). The official GDP is revised by %{change}. The IMF has not taken it in yet: the official figure is shown now, and counts in the African total and the rankings once checked.",
          new: @r["new_base"],
          old: @r["old_base"],
          change: plain_pct(@r["level_change_pct"], @locale)
        )}
      </p>
      <a href={@r["source_url"]} rel="noopener">{gettext("The source")} →</a>
    </div>
    """
  end

  attr :entry, :map, default: nil
  attr :profile, :map, required: true
  attr :to, :integer, required: true
  attr :locale, :string, required: true

  @doc """
  The country's key figures twice: the IMF's for the chosen year and the
  latest official one, with its period, base, source and status.
  """
  def figures_panel(assigns) do
    entry = assigns.entry

    cards =
      for {ind, label, imf_key} <- [
            {"gdp_usd_bn", gettext("GDP"), "gdp_usd_bn"},
            {"public_debt_pct_gdp", gettext("Public debt"), "public_debt_pct_gdp"},
            {"gdp_per_capita", gettext("GDP per capita"), "gdp_per_capita_usd"}
          ],
          fig = pick(entry, ind, assigns.to),
          fig != nil do
        year = fig["year"]

        %{
          id: ind,
          label: label,
          year: year,
          imf: PublicData.at(assigns.profile["series"][imf_key], year),
          imf_key: imf_key,
          figure: fig,
          value_text:
            if(ind == "gdp_per_capita",
              do:
                Format.money_value(fig["per_capita"], "gdp_per_capita_usd", assigns.locale, year),
              else: Format.money_value(fig["value"], ind, assigns.locale, year)
            ),
          per_capita?: ind == "gdp_per_capita"
        }
      end

    assigns = assign(assigns, :cards, cards)

    ~H"""
    <div :if={@cards != []} class="national-figures stack gap-3" id="national-figures">
      <div class="stack gap-1">
        <p class="eyebrow">{gettext("IMF and official figures")}</p>
        <h2 class="h2">{gettext("What the IMF says, what the country publishes")}</h2>
      </div>
      <div class="grid grid-3">
        <div :for={c <- @cards} class="card national-card" id={"national-card-#{c.id}"}>
          <p class="eyebrow">{c.label} · {c.year}</p>
          <div class="national-line">
            <span class="national-src">{gettext("IMF")}</span>
            <span class="national-val num">{Format.money_value(c.imf, c.imf_key, @locale, c.year)}</span>
          </div>
          <span class="small muted">{gettext("World Economic Outlook, comparable between countries")}</span>
          <hr class="national-sep" />
          <div class="national-line">
            <span class="national-src">{gettext("Official")}</span>
            <span class="national-val num">{c.value_text}</span>
          </div>
          <span class="small muted">
            <%= if c.per_capita? do %>
              {gettext("Official GDP ÷ IMF population · Syli Atlas calculation")}
            <% else %>
              {period_text(c.figure)}
            <% end %>
          </span>
          <div class="row gap-1">
            <.status_badge figure={c.figure} />
            <span :if={c.figure["gap_pct"] && !c.per_capita?} class="small muted">
              {gettext("%{gap} from the IMF", gap: signed_pct(c.figure["gap_pct"], @locale))}
            </span>
          </div>
          <p :if={c.figure["status"] == "pending_review"} class="small muted">
            {gettext(
              "Gap or source to confirm: a person checks it before it counts in the African total and the rankings."
            )}
          </p>
          <a :if={!c.per_capita?} class="small" href={c.figure["source_url"]} rel="noopener">
            {c.figure["source_name"]}
          </a>
        </div>
      </div>
      <p class="src">
        {gettext("The two series are never joined: the IMF's stays as published.")}
        <a href={Paths.national(@locale)}>{gettext("The African total, country by country")} →</a>
      </p>
    </div>
    """
  end

  # The figure of the year, else the latest; per capita from the GDP figure.
  defp pick(nil, _ind, _to), do: nil

  defp pick(entry, "gdp_per_capita", to) do
    case pick(entry, "gdp_usd_bn", to) do
      %{"per_capita" => pc} = f when is_number(pc) -> f
      _ -> nil
    end
  end

  defp pick(entry, ind, to), do: National.figure(entry, ind, to) || National.latest(entry, ind)

  @doc "« 2024/25 fiscal year · base 2024/25 · 24,030 bn ETB »."
  def period_text(f) do
    [
      gettext("Period %{period}", period: f["period"]),
      f["base_year"] && gettext("base %{year}", year: f["base_year"]),
      is_number(f["value_lcu"]) &&
        Format.number(f["value_lcu"] / 1.0e9, 0, Gettext.get_locale(SyliAtlasWeb.Gettext)) <>
          " " <> gettext("bn") <> " " <> (f["currency"] || "")
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  defp day(iso, locale) do
    case Date.from_iso8601(iso || "") do
      {:ok, d} -> SyliAtlasWeb.Dates.day_month_year(d.day, d.month, d.year, locale)
      _ -> iso
    end
  end

  def plain_pct(nil, _locale), do: "—"
  def plain_pct(v, locale), do: Format.number(v * 1.0, 1, locale) <> "\u00A0%"

  @doc """
  Puts safe HTML (money spans) into a translated sentence: the sentence
  is translated with `"\\u0000name\\u0000"` markers, then each marker is
  replaced by its value and the text around it is escaped.
  """
  def rich(text, values) do
    text
    |> String.split("\u0000")
    |> Enum.with_index()
    |> Enum.map(fn
      {part, i} when rem(i, 2) == 1 -> Keyword.fetch!(values, String.to_existing_atom(part))
      {part, _} -> Phoenix.HTML.html_escape(part)
    end)
    |> then(&{:safe, Enum.map(&1, fn v -> Phoenix.HTML.Safe.to_iodata(v) end)})
  end

  def signed_pct(nil, _locale), do: "—"

  def signed_pct(v, locale),
    do: if(v > 0, do: "+", else: "") <> Format.number(v * 1.0, 1, locale) <> " %"

  attr :group, :map, default: nil, doc: "SyliAtlas.National.group/3"
  attr :locale, :string, required: true
  attr :id, :string, default: "national-group"

  @doc """
  A group's GDP twice (a region, a community, the continent): the sum of the
  members' IMF figures and the sum of their national figures, with what it
  uses and the figures being checked.
  """
  def group_sum(assigns) do
    ~H"""
    <div :if={@group && @group["members"] > 0} class="card national-group" id={@id}>
      <div class="national-group-cols">
        <div class="stack gap-1">
          <span class="national-src">{gettext("GDP %{year} · IMF", year: @group["year"])}</span>
          <span class="national-val num">
            {Format.money_value(@group["imf_total"], "gdp_usd_bn", @locale, @group["year"])}
          </span>
        </div>
        <div class="stack gap-1">
          <span class="national-src">{gettext("Sum of national figures")}</span>
          <span class="national-val num">
            {Format.money_value(@group["national_total"], "gdp_usd_bn", @locale, @group["year"])}
          </span>
        </div>
      </div>
      <p class="small muted">
        {ngettext(
          "1 country with its official figure",
          "%{count} countries with their official figure",
          @group["counted"]
        )} · {ngettext(
          "1 with the IMF figure (fallback)",
          "%{count} with the IMF figure (fallback)",
          @group["fallback"]
        )}
      </p>
      <p :if={@group["after_review_total"]} class="small national-wait">
        <span class="pill pill-warn">{gettext("Being checked")}</span>
        {rich(
          gettext("Once checked, the sum will be %{total} (%{gap} from the IMF).",
            total: "\u0000total\u0000",
            gap: signed_pct(@group["after_review_gap_pct"], @locale)
          ),
          total:
            Format.money_value(@group["after_review_total"], "gdp_usd_bn", @locale, @group["year"])
        )}
      </p>
      <a class="small" href={Paths.national(@locale)}>{gettext("The total, country by country")} →</a>
    </div>
    """
  end

  @doc """
  The countries whose official GDP of `year` is being checked, for the home
  window: name, amount and the date of their rebasing if any. `names`
  (code → name) comes from the page's snapshot: no query.
  """
  def waiting(doc, year, names) do
    case National.africa(doc, year) do
      %{"rows" => rows} ->
        codes = for r <- rows, is_number(r["pending"]), do: r

        for r <- codes do
          rebasing = get_in(doc, ["countries", r["code"], "rebasing"])

          %{
            code: r["code"],
            name: names[r["code"]] || r["code"],
            amount: r["pending"],
            rebased_on: rebasing && rebasing["active"] && rebasing["announced_on"]
          }
        end

      _ ->
        []
    end
  end

  attr :africa, :map, default: nil
  attr :locale, :string, required: true
  attr :waiting, :list, default: [], doc: "see waiting/3"

  attr :imf, :any,
    default: nil,
    doc:
      "Africa's IMF GDP of the year: shown beside the sum (home hero, canvas « La carte en vitrine »)"

  @doc """
  The sum of national figures (canvas « Accueil · PIB »). With `imf`, the
  IMF's total and the sum stand side by side, as in the home hero.
  """
  def africa_sum(assigns) do
    ~H"""
    <div
      :if={@africa}
      class={["national-sum stack gap-3", @imf && "card national-sum-hero"]}
      id="national-sum"
    >
      <div :if={@imf} class="national-sum-pair">
        <div class="stack gap-1">
          <span class="national-src">{gettext("GDP of Africa %{year} · IMF", year: @africa["year"])}</span>
          <span class="num national-sum-total">
            {Format.money_value(@imf, "gdp_usd_bn", @locale, @africa["year"])}
          </span>
        </div>
        <div class="stack gap-1">
          <span class="national-src">{gettext("Sum of national figures")}</span>
          <span class="num national-sum-total">
            {Format.money_value(@africa["national_total"], "gdp_usd_bn", @locale, @africa["year"])}
          </span>
        </div>
      </div>
      <div :if={!@imf} class="stack gap-1">
        <span class="national-src">{gettext("Sum of national figures")}</span>
        <span class="num national-sum-total">
          {Format.money_value(@africa["national_total"], "gdp_usd_bn", @locale, @africa["year"])}
        </span>
      </div>
      <span class="small muted">
        {gettext(
          "Official figure checked when the country publishes one, otherwise the IMF's for the same year"
        )}
      </span>
      <div class="stack gap-2">
        <div
          class="national-bar"
          role="img"
          aria-label={
            gettext(
              "Composition: %{national} % national figures, %{pending} % being checked, the rest IMF figures as fallback",
              national: Format.number(@africa["national_share_pct"] || 0.0, 0, @locale),
              pending: Format.number(@africa["pending_share_pct"] || 0.0, 0, @locale)
            )
          }
        >
          <span class="national-bar-nat" style={"width: #{@africa["national_share_pct"] || 0}%"}></span>
          <span class="national-bar-imf"></span>
          <span class="national-bar-wait" style={"width: #{@africa["pending_share_pct"] || 0}%"}></span>
        </div>
        <ul class="national-legend" role="list">
          <li :if={@africa["counted"] > 0}>
            <i class="national-bar-nat"></i>
            {ngettext(
              "1 country with its official figure",
              "%{count} countries with their official figure",
              @africa["counted"]
            )}
          </li>
          <li class="muted">
            <i class="national-bar-imf"></i>
            {ngettext(
              "1 country with the IMF figure (fallback)",
              "%{count} countries with the IMF figure (fallback)",
              @africa["fallback"]
            )}
          </li>
          <li :if={@africa["pending"] != []}>
            <i class="national-bar-wait"></i>
            {ngettext(
              "1 country being checked",
              "%{count} countries being checked",
              length(@africa["pending"] || [])
            )}
          </li>
        </ul>
      </div>
      <p :if={@africa["after_review_total"]} class="national-wait">
        <span class="pill pill-warn">{gettext("Being checked")}</span>
        <span>
          <%= for w <- @waiting do %>
            {rich(
              if(w.rebased_on,
                do:
                  gettext("%{country}: %{amount} (rebased %{date}).",
                    country: w.name,
                    amount: "\u0000amount\u0000",
                    date: day(w.rebased_on, @locale)
                  ),
                else: gettext("%{country}: %{amount}.", country: w.name, amount: "\u0000amount\u0000")
              ),
              amount: Format.money_value(w.amount, "gdp_usd_bn", @locale, @africa["year"])
            )}
          <% end %>
          {rich(
            gettext("Once checked, the sum will be %{total} (%{diff}, %{gap}).",
              total: "\u0000total\u0000",
              diff: "\u0000diff\u0000",
              gap: signed_pct(@africa["after_review_gap_pct"], @locale)
            ),
            total:
              Format.money_value(
                @africa["after_review_total"],
                "gdp_usd_bn",
                @locale,
                @africa["year"]
              ),
            diff:
              signed_money(
                @africa["after_review_total"] - @africa["national_total"],
                @locale,
                @africa["year"]
              )
          )}
        </span>
      </p>
      <a class="national-more" href={Paths.national(@locale)}>
        {gettext("The total, country by country")} →
      </a>
    </div>
    """
  end

  # "+75 Md$": the gap in billions, signed, in the reader's currency.
  defp signed_money(v, locale, year) do
    sign = if v >= 0, do: "+", else: "−"
    money = Format.money_value(abs(v), "gdp_usd_bn", locale, year)
    {:safe, [sign, Phoenix.HTML.Safe.to_iodata(money)]}
  end
end
