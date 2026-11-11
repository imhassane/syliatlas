defmodule SyliAtlasWeb.RecapHTML do
  use SyliAtlasWeb, :html

  alias SyliAtlasWeb.Paths

  embed_templates "recap_html/*"

  def frequency_label("monthly"), do: gettext("on the 1st of each month")
  def frequency_label(_weekly), do: gettext("every Monday")

  @doc """
  The countries to choose, by region, as checkboxes styled as chips:
  works without JavaScript. At most `max` are taken (checked server-side).
  """
  attr :regions, :list, required: true
  attr :picked, :any, required: true
  attr :max, :integer, required: true

  def country_picker(assigns) do
    ~H"""
    <fieldset class="recap-picker" id="recap-countries">
      <legend class="h2">{gettext("Your countries")}</legend>
      <p class="small muted">
        {gettext("Up to %{max}. The recap starts with those that had news.", max: @max)}
      </p>
      <div :for={r <- @regions} class="recap-region">
        <p class="eyebrow">{r.name}</p>
        <div class="recap-chips">
          <label :for={c <- r.countries} class="recap-chip">
            <input
              type="checkbox"
              name="countries[]"
              value={c.code}
              checked={MapSet.member?(@picked, c.code)}
            />
            <span>{c.name}</span>
          </label>
        </div>
      </div>
    </fieldset>
    """
  end

  attr :frequency, :string, required: true

  def frequency_picker(assigns) do
    ~H"""
    <fieldset class="recap-frequency" id="recap-frequency">
      <legend class="h2">{gettext("Frequency")}</legend>
      <label class="recap-radio">
        <input type="radio" name="frequency" value="weekly" checked={@frequency != "monthly"} />
        {gettext("Every Monday")}
      </label>
      <label class="recap-radio">
        <input type="radio" name="frequency" value="monthly" checked={@frequency == "monthly"} />
        {gettext("On the 1st of each month")}
      </label>
    </fieldset>
    """
  end
end
