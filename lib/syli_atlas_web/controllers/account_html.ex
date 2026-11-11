defmodule SyliAtlasWeb.AccountHTML do
  use SyliAtlasWeb, :html

  alias SyliAtlas.Accounts
  alias SyliAtlas.Accounts.{Alert, Session}
  alias SyliAtlasWeb.Paths

  import SyliAtlasWeb.SessionHTML, only: [passkey_button: 1]

  embed_templates "account_html/*"

  attr :locale, :string, required: true
  attr :user, :any, required: true
  attr :tab, :atom, required: true
  slot :inner_block, required: true

  @doc "The frame of the space: the account and its tabs, then the page."
  def space(assigns) do
    ~H"""
    <section class="section section-alt space">
      <div class="wrap space-grid">
        <aside class="space-side stack gap-3">
          <div class="space-who">
            <span class="avatar" aria-hidden="true">{initials(@user.email)}</span>
            <span class="stack">
              <b dir="ltr">{@user.email}</b>
              <span :if={@user.role == "admin"} class="pill pill-info">{gettext("administrator")}</span>
            </span>
          </div>
          <nav class="space-nav" aria-label={gettext("My space")}>
            <a
              :for={{tab, label} <- tabs()}
              href={Paths.account(@locale, tab)}
              aria-current={@tab == tab && "page"}
            >
              {label}
            </a>
          </nav>
          <a :if={@user.role == "admin"} class="btn btn-secondary" href={~p"/admin"} id="space-admin">
            {gettext("Administration")}
          </a>
          <.form for={%{}} action={~p"/account/session"} method="delete" id="sign-out">
            <button class="btn btn-quiet" type="submit">{gettext("Sign out")}</button>
          </.form>
        </aside>
        <div class="space-main stack gap-4">
          {render_slot(@inner_block)}
        </div>
      </div>
    </section>
    """
  end

  defp tabs,
    do: [
      {:favorites, gettext("Favourites")},
      {:alerts, gettext("Alerts")},
      {:security, pgettext("account", "Security")}
    ]

  defp initials(email), do: email |> String.slice(0, 2) |> String.upcase()

  def kind_label("area"), do: gettext("Country or region")
  def kind_label("exchange"), do: gettext("Exchange")
  def kind_label("security"), do: gettext("Security")
  def kind_label("comparison"), do: gettext("Comparison")

  def alert_kinds,
    do: [
      {"rating_change", gettext("a rating agency acts (new rating or outlook)")},
      {"new_edition", gettext("the IMF publishes new figures")},
      {"indicator_above", gettext("an indicator goes above a threshold")},
      {"indicator_below", gettext("an indicator goes below a threshold")}
    ]

  def indicators,
    do: [
      {"real_gdp_growth", gettext("Real GDP growth (%)")},
      {"inflation", gettext("Inflation (%)")},
      {"public_debt_pct_gdp", gettext("Public debt (% of GDP)")},
      {"fiscal_balance_pct_gdp", gettext("Budget balance (% of GDP)")},
      {"current_account_pct_gdp", gettext("Current account (% of GDP)")},
      {"gdp_per_capita_usd", gettext("GDP per capita (US$)")},
      {"unemployment", gettext("Unemployment (%)")}
    ]

  def frequencies,
    do: [{"immediate", gettext("Immediately")}, {"weekly", gettext("In the weekly digest")}]

  def digests,
    do: [
      {"weekly", gettext("Every Monday")},
      {"monthly", gettext("On the 1st of the month")},
      {"never", gettext("Never")}
    ]

  def market_kinds,
    do: [
      {"session_move", gettext("moves more than a percentage in one session (up or down)")},
      {"price_above", gettext("closes above a price")},
      {"price_below", gettext("closes below a price")}
    ]

  @doc "What an alert watches, in a sentence."
  def describe(%Alert{kind: kind} = alert, _countries, _locale)
      when kind in ~w(session_move price_above price_below) do
    subject =
      case alert.ticker do
        nil -> gettext("%{exchange} · index", exchange: String.upcase(alert.exchange_code))
        ticker -> "#{ticker} · #{String.upcase(alert.exchange_code)}"
      end

    rule =
      case kind do
        "session_move" ->
          gettext("session move of %{threshold} % or more", threshold: threshold(alert.threshold))

        "price_above" ->
          gettext("close above %{threshold}", threshold: threshold(alert.threshold))

        "price_below" ->
          gettext("close below %{threshold}", threshold: threshold(alert.threshold))
      end

    {subject, rule}
  end

  def describe(%Alert{} = alert, countries, locale) do
    country =
      case Enum.find(countries, &(&1.code == alert.area_code)) do
        nil -> alert.area_code
        area -> SyliAtlas.Geo.Area.name(area, locale)
      end

    rule =
      case alert.kind do
        "rating_change" ->
          gettext("any rating action")

        "new_edition" ->
          gettext("new IMF figures")

        "indicator_above" ->
          gettext("%{indicator} above %{threshold}",
            indicator: indicator_name(alert.indicator),
            threshold: threshold(alert.threshold)
          )

        "indicator_below" ->
          gettext("%{indicator} below %{threshold}",
            indicator: indicator_name(alert.indicator),
            threshold: threshold(alert.threshold)
          )
      end

    {country, rule}
  end

  defp indicator_name(code), do: indicators() |> List.keyfind(code, 0, {code, code}) |> elem(1)
  defp threshold(nil), do: ""
  defp threshold(d), do: d |> Decimal.to_string(:normal) |> String.replace(".", ",")

  def frequency_label(f), do: frequencies() |> List.keyfind(f, 0, {f, f}) |> elem(1)

  def when_label(nil, _locale), do: gettext("never")
  def when_label(at, _locale), do: Calendar.strftime(at, "%d/%m/%Y %H:%M") <> " UTC"

  def device(%Session{user_agent: ua}), do: Accounts.device_name(ua)

  def proofs(%Session{} = s) do
    [s.code_verified_at && gettext("email code"), s.passkey_verified_at && gettext("passkey")]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" + ")
  end
end
