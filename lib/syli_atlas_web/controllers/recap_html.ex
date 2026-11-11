defmodule SyliAtlasWeb.RecapHTML do
  use SyliAtlasWeb, :html

  alias SyliAtlasWeb.Paths

  embed_templates "recap_html/*"

  def frequency_label("monthly"), do: gettext("on the 1st of each month")
  def frequency_label(_weekly), do: gettext("every Monday")

  @doc "Names of the picked countries, in the order of the regions."
  def picked_names(regions, picked) do
    for r <- regions, c <- r.countries, MapSet.member?(picked, c.code), do: c.name
  end

  @doc """
  Step « choose your countries » (canvas « Page 2 »): every country as a
  checkbox styled as a chip with its flag, as wide as its name, grouped by
  region. Without JavaScript the
  regions follow each other; with it (`initRecapPage`), tabs filter them.
  At most `max` are taken (checked server-side).
  """
  attr :regions, :list, required: true
  attr :picked, :any, required: true
  attr :max, :integer, required: true
  attr :n, :integer, default: 1

  def country_picker(assigns) do
    ~H"""
    <section class="recap-step" aria-labelledby="recap-step-countries">
      <h2 class="recap-step-title" id="recap-step-countries">
        <span aria-hidden="true">{@n}</span>{gettext("Choose your countries")}
      </h2>
      <div class="recap-tabs" role="group" aria-label={gettext("Regions")} data-recap-tabs hidden>
        <button type="button" class="recap-tab" aria-pressed="true" data-region="">
          {gettext("All")}
        </button>
        <button
          :for={r <- @regions}
          type="button"
          class="recap-tab"
          aria-pressed="false"
          data-region={r.code}
        >
          {r.name}
        </button>
      </div>
      <fieldset class="recap-picker" id="recap-countries">
        <legend class="vh">{gettext("Countries")}</legend>
        <div :for={r <- @regions} class="recap-region" data-region={r.code}>
          <p class="eyebrow">{r.name}</p>
          <div class="recap-chips">
            <label :for={c <- r.countries} class="recap-chip">
              <input
                type="checkbox"
                name="countries[]"
                value={c.code}
                checked={MapSet.member?(@picked, c.code)}
              />
              <span><.flag code={c.code} size="sm" sprite />{c.name}</span>
            </label>
          </div>
        </div>
      </fieldset>
      <p class="small muted">
        {gettext("Up to %{max}. The recap starts with those that had news.", max: @max)}
      </p>
    </section>
    """
  end

  attr :frequency, :string, required: true
  attr :n, :integer, default: 2

  def frequency_picker(assigns) do
    ~H"""
    <section class="recap-step" aria-labelledby="recap-step-rhythm">
      <h2 class="recap-step-title" id="recap-step-rhythm">
        <span aria-hidden="true">{@n}</span>{gettext("Choose the rhythm")}
      </h2>
      <fieldset class="recap-rhythm" id="recap-frequency">
        <legend class="vh">{gettext("Frequency")}</legend>
        <label class="recap-option">
          <input
            type="radio"
            name="frequency"
            value="weekly"
            checked={@frequency != "monthly"}
            data-label={frequency_label("weekly")}
          />
          <b>{gettext("Every Monday")}</b>
          <span>{gettext("The news of the past 7 days")}</span>
        </label>
        <label class="recap-option">
          <input
            type="radio"
            name="frequency"
            value="monthly"
            checked={@frequency == "monthly"}
            data-label={frequency_label("monthly")}
          />
          <b>{gettext("On the 1st of each month")}</b>
          <span>{gettext("The past month, in brief")}</span>
        </label>
      </fieldset>
    </section>
    """
  end

  @doc "The bar at the bottom of the form: what is chosen, and the button."
  attr :names, :list, required: true
  attr :frequency, :string, required: true
  attr :max, :integer, required: true
  slot :inner_block, required: true

  def summary_bar(assigns) do
    ~H"""
    <div
      class="recap-bar"
      data-recap-summary
      data-max={@max}
      data-none={gettext("No country chosen yet")}
    >
      <div class="recap-bar-text" aria-live="polite">
        <b data-recap-names>{summary_names(@names)}</b>
        <span>
          <span data-recap-count>{length(@names)}</span>
          {gettext("of %{max} countries", max: @max)} ·
          <span data-recap-frequency>{frequency_label(@frequency)}</span>
        </span>
      </div>
      <div class="recap-bar-actions">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  defp summary_names([]), do: gettext("No country chosen yet")
  defp summary_names(names), do: Enum.join(names, ", ")
end
