defmodule SyliAtlasWeb.ClimateComponents do
  @moduledoc """
  The « Business climate » section of a country profile: World Bank
  indicators, each against the African median. No verdict of our own.
  """
  use SyliAtlasWeb, :html

  def wgi_label("regulatory_quality"), do: gettext("Regulatory quality")
  def wgi_label("rule_of_law"), do: gettext("Rule of law")
  def wgi_label("government_effectiveness"), do: gettext("Government effectiveness")
  def wgi_label("control_of_corruption"), do: gettext("Control of corruption")

  def wgi_hint("regulatory_quality"),
    do: gettext("Can the state make and apply rules that let private business grow?")

  def wgi_hint("rule_of_law"),
    do: gettext("Are contracts, property rights, the police and the courts reliable?")

  def wgi_hint("government_effectiveness"),
    do: gettext("Quality of public services and of the administration.")

  def wgi_hint("control_of_corruption"),
    do: gettext("How far public power is used for private gain.")

  def bready_label("regulatory_framework"), do: gettext("Regulatory framework")
  def bready_label("public_services"), do: gettext("Public services for firms")
  def bready_label("operational_efficiency"), do: gettext("Operational efficiency")

  def headline("above", name),
    do: gettext("%{name}: a business climate better than in most African countries", name: name)

  def headline("below", name),
    do: gettext("%{name}: a business climate harder than in most African countries", name: name)

  def headline(_, name),
    do: gettext("%{name}: a business climate close to the African median", name: name)

  def position_text(%{"above" => above, "of" => of}),
    do:
      ngettext(
        "Above the African median on %{count} indicator out of %{of}.",
        "Above the African median on %{count} indicators out of %{of}.",
        above,
        of: of
      )

  @doc "Question and answer for the profile's FAQ."
  def faq_items(_name, nil), do: []
  def faq_items(_name, false), do: []

  def faq_items(name, entry) do
    bready =
      case entry["bready"] do
        %{"overall" => o} ->
          " " <>
            gettext("B-READY: %{score}/100, no. %{rank} of %{of} African economies covered.",
              score: score(o["score"]),
              rank: o["rank"],
              of: o["of"]
            )

        _ ->
          ""
      end

    [
      {gettext("Is %{name} business friendly?", names(name)),
       headline(entry["position"]["tier"], name) <>
         ". " <> position_text(entry["position"]) <> bready}
    ]
  end

  def score(nil), do: "—"
  def score(v), do: :erlang.float_to_binary(v / 1, decimals: 1)

  attr :entry, :map, required: true
  attr :name, :string, required: true
  attr :doc, :map, required: true

  def climate_section(assigns) do
    ~H"""
    <section class="section" id="climat">
      <div class="wrap stack gap-4">
        <div class="section-head">
          <p class="eyebrow">{gettext("Business climate")}</p>
          <h2 class="h1">{headline(@entry["position"]["tier"], @name)}</h2>
          <p class="lead">
            {position_text(@entry["position"])}
            {gettext(
              "Syli Atlas gives no « business friendly » verdict of its own: each score comes from the World Bank, compared with the other African countries."
            )}
          </p>
        </div>

        <div class="grid grid-2">
          <div :if={@entry["wgi"]} class="card pad stack gap-3" id="climate-wgi">
            <div>
              <h3 class="h3">{gettext("Governance")}</h3>
              <p class="small muted">
                {gettext("Worldwide Governance Indicators %{year}, score from 0 to 100",
                  year: @doc["sources"]["wgi"]["year"]
                )}
              </p>
            </div>
            <.climate_bar
              :for={key <- SyliAtlas.Climate.wgi_keys()}
              label={wgi_label(key)}
              hint={wgi_hint(key)}
              item={@entry["wgi"][key]}
            />
          </div>

          <div class="card pad stack gap-3" id="climate-bready">
            <div>
              <h3 class="h3">{gettext("Business regulations and services")}</h3>
              <p class="small muted">
                {gettext("World Bank Business Ready (B-READY) %{year}, score from 0 to 100",
                  year: @doc["sources"]["bready"]["year"]
                )}
              </p>
            </div>
            <%= if b = @entry["bready"] do %>
              <p class="row gap-2">
                <span class="num rt-big">{score(b["overall"]["score"])}</span>
                <span class="small muted">
                  {gettext(
                    "average of the three pillars · no. %{rank} of the %{of} African economies covered",
                    rank: b["overall"]["rank"],
                    of: b["overall"]["of"]
                  )}
                </span>
              </p>
              <.climate_bar
                :for={key <- SyliAtlas.Climate.bready_keys()}
                label={bready_label(key)}
                item={b[key]}
              />
            <% else %>
              <p class="muted" id="climate-bready-none">
                {gettext(
                  "%{name} is not covered yet: B-READY adds countries edition after edition (%{count} African economies in the latest one).",
                  names(@name, count: @doc["covered"]["bready"])
                )}
              </p>
            <% end %>
          </div>
        </div>

        <p class="src">
          {gettext(
            "Sources: World Bank, Worldwide Governance Indicators (CC BY 4.0) and Business Ready (CC BY 3.0 IGO) · the line marks the African median · ranks among the African countries covered"
          )}
        </p>
      </div>
    </section>
    """
  end

  attr :label, :string, required: true
  attr :hint, :string, default: nil
  attr :item, :map, required: true

  defp climate_bar(assigns) do
    ~H"""
    <div class="cl-row">
      <div class="cl-head">
        <span>{@label}</span>
        <span class="num">
          <b>{score(@item["score"])}</b>
          <span class={["small", if(@item["above"], do: "up", else: "down")]}>
            {gettext("no. %{rank} of %{of}", rank: @item["rank"], of: @item["of"])}
          </span>
        </span>
      </div>
      <div
        class="rt-bar-track cl-track"
        role="img"
        aria-label={
          gettext("%{label}: %{score} out of 100, African median %{median}",
            label: @label,
            score: score(@item["score"]),
            median: score(@item["median"])
          )
        }
      >
        <span
          class={["rt-bar-fill", if(@item["above"], do: "cl-above", else: "cl-below")]}
          style={"width: #{@item["score"]}%"}
        ></span>
        <span class="rt-bar-line" style={"left: #{@item["median"]}%"}></span>
      </div>
      <p :if={@hint} class="small muted">{@hint}</p>
    </div>
    """
  end
end
