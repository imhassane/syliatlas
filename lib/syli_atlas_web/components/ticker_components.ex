defmodule SyliAtlasWeb.TickerComponents do
  @moduledoc """
  The scrolling band under the header of every public page: indices at the
  last close, then the latest rating decisions (see `SyliAtlasWeb.Ticker`).

  The list is written twice so the loop is seamless; the copy is hidden from
  screen readers and skipped by the keyboard. The band pauses on hover and
  on keyboard focus, has a pause button (shown by the script, remembered on
  the device), and stays still when the reader asked for less motion.
  """
  use Phoenix.Component
  use Gettext, backend: SyliAtlasWeb.Gettext

  alias SyliAtlas.Market.Catalog
  alias SyliAtlas.Ratings.Scale
  alias SyliAtlasWeb.{MarketComponents, Paths, RatingComponents}

  # Seconds of scrolling per item: the speed stays the same whatever the length.
  @seconds_per_item 4

  attr :locale, :string, required: true
  attr :data, :map, default: nil, doc: "from SyliAtlasWeb.Ticker.get/0 (read when nil)"

  def site_ticker(assigns) do
    data = assigns.data || SyliAtlasWeb.Ticker.get()
    count = length(data.indices) + length(data.ratings)

    assigns =
      assigns
      |> assign(:data, data)
      |> assign(:count, count)
      |> assign(:duration, max(count, 6) * @seconds_per_item)
      |> assign(:credits, credits(data.market_sources))

    ~H"""
    <div
      :if={@count > 0}
      class="site-ticker"
      id="site-ticker"
      role="region"
      aria-label={gettext("Stock exchanges and sovereign ratings")}
      data-ticker
    >
      <button
        type="button"
        class="site-ticker-pause"
        id="site-ticker-pause"
        aria-pressed="false"
        aria-label={gettext("Pause the scrolling")}
        data-label-pause={gettext("Pause the scrolling")}
        data-label-play={gettext("Resume the scrolling")}
        data-ticker-pause
        hidden
      >
        <svg
          class="i-pause"
          width="16"
          height="16"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          aria-hidden="true"
        ><path d="M9 5v14M15 5v14"></path></svg>
        <svg
          class="i-play"
          width="16"
          height="16"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linejoin="round"
          aria-hidden="true"
        ><path d="M7 5l12 7-12 7z"></path></svg>
      </button>
      <div class="site-ticker-view">
        <div class="site-ticker-track" style={"--ticker-duration: #{@duration}s"}>
          <ul :for={copy <- [false, true]} class="site-ticker-list" aria-hidden={copy && "true"}>
            <li :if={@data.indices != []} class="site-ticker-head">
              {gettext("Stock exchanges")}
              <span :if={@data.market_date}>
                {gettext("close of %{date}",
                  date: MarketComponents.day(@data.market_date, @locale, year: false)
                )}
              </span>
            </li>
            <li :for={x <- @data.indices}>
              <a href={Paths.exchange(@locale, x.code)} tabindex={copy && "-1"}>
                <b>{x.name}</b>
                <span class="muted site-ticker-detail">{MarketComponents.price(x.value, @locale)}</span>
                <span class={MarketComponents.tone(x.change_pct)}>
                  {MarketComponents.pct(x.change_pct, @locale)}
                </span>
              </a>
            </li>
            <li :if={@data.ratings != []} class="site-ticker-head">
              {gettext("Ratings")} <span>{gettext("latest decisions")}</span>
            </li>
            <li :for={r <- @data.ratings}>
              <a
                href={Paths.rating(@locale, SyliAtlas.Locales.pick(r.slug, @locale))}
                tabindex={copy && "-1"}
              >
                <b>{SyliAtlas.Locales.pick(r.name, @locale)}</b>
                <span class="mono muted">
                  <span class="site-ticker-detail">{RatingComponents.agency_name(r.agency)}</span>
                  {Scale.display(r.rating)}
                </span>
                <span class={action_tone(r.action)}>{action_text(r.action)}</span>
                <span class="subtle site-ticker-detail">{date_text(r.date, @locale)}</span>
              </a>
            </li>
          </ul>
        </div>
      </div>
      <p :if={@data.indices != []} class="site-ticker-credit">
        <%= if SyliAtlas.Market.fake?() do %>
          <b>{gettext("Fictitious figures")}</b> ·
        <% end %>
        <%= for {s, i} <- Enum.with_index(@credits) do %>
          {if i > 0, do: ", "}<a href={Catalog.url(s["code"]) || s["url"]} rel="noopener">{Catalog.attribution(
            s["code"]
          )}</a>
          ·
        <% end %>
        <span>{gettext("end of day")}</span>
      </p>
    </div>
    """
  end

  defp credits(sources) do
    if SyliAtlas.Market.fake?(), do: [], else: Enum.filter(sources, &(&1["rank"] == 1))
  end

  @doc false
  def action_text("upgrade"), do: "▲ " <> gettext("upgraded")
  def action_text("downgrade"), do: "▼ " <> gettext("downgraded")
  def action_text("default"), do: "▼ " <> gettext("default")
  def action_text("outlook_up"), do: "↗ " <> gettext("outlook raised")
  def action_text("outlook_down"), do: "↘ " <> gettext("outlook lowered")

  defp action_tone(action) when action in ~w(upgrade outlook_up), do: "up"
  defp action_tone(_), do: "down"

  # « 30 oct. »: the year only when it is not the current one.
  defp date_text(iso, locale) do
    case Date.from_iso8601(iso) do
      {:ok, d} -> MarketComponents.day(iso, locale, year: d.year != Date.utc_today().year)
      _ -> RatingComponents.date_text(iso, locale)
    end
  end
end
