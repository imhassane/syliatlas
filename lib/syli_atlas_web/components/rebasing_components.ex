defmodule SyliAtlasWeb.RebasingComponents do
  @moduledoc """
  The rebasing alert (decisions of 15 Nov. 2026): a chip in the country's
  header, a folded panel in its Economy tab, a line once the IMF has taken
  the rebasing in, and the sentences the title, description and structured
  data reuse. Everything is in the HTML served, not added by JavaScript.
  """
  use SyliAtlasWeb, :html

  alias SyliAtlas.National.Rebasings
  alias SyliAtlasWeb.{Dates, Format, NationalComponents, Paths}

  @doc "« GDP rebased on 4 Nov. 2026 · +59.2 % »: the chip of the header."
  def chip_label(n, locale) do
    case n["level_change_pct"] do
      v when is_number(v) ->
        gettext("GDP rebased on %{date} · %{change}",
          date: day(n["announced_on"], locale),
          change: signed_pct(v, locale)
        )

      _ ->
        gettext("GDP rebased on %{date}", date: day(n["announced_on"], locale))
    end
  end

  @doc """
  One sentence for the description and the structured data of the page:
  the rebasing, and that the IMF has not taken it in yet.
  """
  def summary(n, name, locale) do
    revision =
      case n["level_change_pct"] do
        v when is_number(v) ->
          gettext(
            "%{name} rebased its GDP on %{date} (%{change}, base %{base}).",
            Format.names(name,
              date: day(n["announced_on"], locale),
              change: signed_pct(v, locale),
              base: n["new_base"]
            )
          )

        _ ->
          gettext(
            "%{name} rebased its GDP on %{date} (base %{base}).",
            Format.names(name, date: day(n["announced_on"], locale), base: n["new_base"])
          )
      end

    revision <> " " <> gettext("The IMF should take it in in a coming edition of its outlook.")
  end

  @doc "The IMF's next World Economic Outlook, « April 2027 »."
  def next_edition(locale) do
    {y, m} = Rebasings.next_imf_edition()
    Dates.month_year(m, y, locale, :long)
  end

  @doc "An edition code (\"2026-10\") as « October 2026 »."
  def edition(code, locale) do
    case Rebasings.edition_month(code) do
      {y, m} -> Dates.month_year(m, y, locale, :long)
      _ -> code
    end
  end

  attr :notice, :map, default: nil
  attr :name, :string, required: true
  attr :official, :map, default: nil, doc: "the country's latest official GDP figure, if any"
  attr :locale, :string, required: true

  @doc """
  The Economy tab's panel, folded: one line, then the details. Once the IMF
  has taken the rebasing in, a single grey line instead.
  """
  def panel(assigns) do
    ~H"""
    <details
      :if={@notice && @notice["active"]}
      class="rebasing-panel"
      id="rebasage"
      aria-labelledby="rebasing-title"
    >
      <summary>
        <span class="pill pill-warn">{gettext("Rebasing")}</span>
        <span class="rebasing-line">
          <b>{headline(@notice, @locale)}</b>
          <span>
            · {gettext("the IMF has not taken it in yet (next edition: %{edition}).",
              edition: next_edition(@locale)
            )}
          </span>
        </span>
        <span class="rebasing-more" aria-hidden="true">{gettext("Details")}</span>
      </summary>
      <div class="rebasing-body">
        <div class="stack gap-1">
          <h2 class="rebasing-title" id="rebasing-title">
            {title(@notice, @name, @locale)}
          </h2>
          <p>
            {gettext("The national accounts move to the base year %{new} (instead of %{old}).",
              new: @notice["new_base"],
              old: @notice["old_base"]
            )}
            <span :if={@official}>
              {NationalComponents.rich(
                gettext("Official figure for %{period}: %{official}, against %{imf} for the IMF.",
                  period: @official["period"],
                  official: "\u0000official\u0000",
                  imf: "\u0000imf\u0000"
                ),
                official:
                  Format.money_value(@official["value"], "gdp_usd_bn", @locale, @official["year"]),
                imf: Format.money_value(@official["imf"], "gdp_usd_bn", @locale, @official["year"])
              )}
            </span>
          </p>
          <p>
            {gettext(
              "The IMF figures on this page are still on the former base. The IMF should take this rebasing in in a coming edition of its World Economic Outlook; the next one is expected in %{edition}.",
              edition: next_edition(@locale)
            )}
          </p>
          <p class="rebasing-links">
            <a href={@notice["source_url"]} rel="noopener">{gettext("The source")} →</a>
            <a href={Paths.rebasings(@locale)}>{gettext("Every rebasing in Africa")} →</a>
          </p>
        </div>
        <dl class="rebasing-facts">
          <dt>{gettext("Announced")}</dt>
          <dd>{day(@notice["announced_on"], @locale)}</dd>
          <dt>{gettext("Base")}</dt>
          <dd>{@notice["old_base"]} → {@notice["new_base"]}</dd>
          <dt :if={is_number(@notice["level_change_pct"])}>{gettext("Revision")}</dt>
          <dd :if={is_number(@notice["level_change_pct"])}>
            {signed_pct(@notice["level_change_pct"], @locale)}
          </dd>
          <dt>{gettext("IMF")}</dt>
          <dd>
            {gettext("Not taken in yet · %{edition} on the former base",
              edition: edition(@notice["imf_edition"], @locale)
            )}
          </dd>
          <dt>{gettext("Expected")}</dt>
          <dd>{gettext("Outlook of %{edition} (or the next)", edition: next_edition(@locale))}</dd>
        </dl>
      </div>
    </details>
    <p
      :if={@notice && !@notice["active"]}
      class="small muted rebasing-history"
      id="rebasing-history"
    >
      {gettext("Rebasing of %{date} (base %{base}) taken in by the IMF in its outlook of %{edition}.",
        date: day(@notice["announced_on"], @locale),
        base: @notice["new_base"],
        edition: edition(@notice["integrated_edition"], @locale)
      )}
      <a href={Paths.rebasings(@locale)}>{gettext("Every rebasing")}</a>
    </p>
    """
  end

  attr :notice, :map, default: nil
  attr :href, :string, required: true
  attr :locale, :string, required: true

  @doc "On the Public finances tab: ratios to GDP still use the former base."
  def ratio_note(assigns) do
    ~H"""
    <p :if={@notice && @notice["active"]} class="small rebasing-note" id="rebasing-ratio-note">
      {gettext("Ratios to GDP are computed on the former base of the GDP.")}
      <a href={@href}>{gettext("See the rebasing")}</a>
    </p>
    """
  end

  defp headline(n, locale) do
    case n["level_change_pct"] do
      v when is_number(v) ->
        gettext("GDP revised by %{change} on %{date}",
          change: signed_pct(v, locale),
          date: day(n["announced_on"], locale)
        )

      _ ->
        gettext("New base year %{base} on %{date}",
          base: n["new_base"],
          date: day(n["announced_on"], locale)
        )
    end
  end

  defp title(n, name, locale) do
    case n["level_change_pct"] do
      v when is_number(v) ->
        gettext(
          "%{name} revised its GDP by %{change}",
          Format.names(name, change: signed_pct(v, locale))
        )

      _ ->
        gettext("%{name} changed the base year of its GDP", Format.names(name))
    end
  end

  def signed_pct(v, locale) when is_number(v) do
    sign = if v > 0, do: "+", else: if(v < 0, do: "−", else: "")
    sign <> Format.number(abs(v) * 1.0, 1, locale) <> " %"
  end

  def day(iso, locale) do
    case Date.from_iso8601(iso || "") do
      {:ok, d} -> Dates.day_month_year(d.day, d.month, d.year, locale)
      _ -> iso
    end
  end
end
