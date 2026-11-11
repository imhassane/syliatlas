defmodule SyliAtlasWeb.ApiDocHTML do
  use SyliAtlasWeb, :html

  embed_templates "api_doc_html/*"

  @doc "French or English text, picked by the page's locale."
  def tr("fr", fr, _en), do: fr
  def tr(_, _fr, en), do: en

  @doc "Microseconds as milliseconds, one decimal, in the page's language: 1,2 ms."
  def ms(nil, _locale), do: "—"

  def ms(us, locale) do
    text = :erlang.float_to_binary(us / 1000, decimals: 1)
    if locale == "fr", do: String.replace(text, ".", ",") <> " ms", else: text <> " ms"
  end

  @errors %{
    "invalid_period" =>
      {"années hors 2015–2030, ou from ≥ to", "years outside 2015–2030, or from ≥ to"},
    "codes_required" => {"aucun code fourni", "no code given"},
    "unknown_indicator" => {"indicateur inconnu", "unknown indicator"},
    "unknown_area" => {"code de zone inconnu", "unknown area code"},
    "not_found" => {"route inconnue", "unknown route"},
    "rate_limited" => {"trop de requêtes", "too many requests"}
  }

  @doc "What an error code means, in the page's language."
  def error_text(code, locale) do
    {fr, en} = Map.get(@errors, code, {code, code})
    tr(locale, fr, en)
  end

  @doc "The label of a unit code, in the page's language."
  def unit_label(nil, _locale), do: nil

  def unit_label(code, locale) do
    Enum.find_value(SyliAtlasWeb.Api.Catalog.units(), code, fn u ->
      u.code == code && if(locale == "fr", do: u.label.fr, else: u.label.en)
    end)
  end

  attr :fields, :list, required: true
  attr :locale, :string, required: true

  @doc "The fields of an answer or a schema: path, type, meaning, values, unit."
  def fields_table(assigns) do
    ~H"""
    <div class="api-ftable" role="table" aria-label={tr(@locale, "Champs", "Fields")}>
      <div class="api-frow api-table-head" role="row">
        <span role="columnheader">{tr(@locale, "Champ", "Field")}</span>
        <span role="columnheader">Type</span>
        <span role="columnheader">{tr(@locale, "Description", "Description")}</span>
      </div>
      <div :for={f <- @fields} class="api-frow" role="row">
        <span role="cell"><code class="api-fpath">{f.path}</code></span>
        <span role="cell" class="api-ftype">
          <a :if={f.link} href={"#schema-" <> f.link}><code>{f.type}</code></a>
          <code :if={!f.link}>{f.type}</code>
        </span>
        <span role="cell" class="api-fdesc">
          {f.desc}
          <span :if={f.values} class="api-fvalues">
            {tr(@locale, "Valeurs", "Values")} : <code>{f.values}</code>
          </span>
          <span :if={f.unit} class="api-fvalues">
            {tr(@locale, "Unité", "Unit")} : {unit_label(f.unit, @locale)}
          </span>
        </span>
      </div>
    </div>
    """
  end

  @months_fr ~w(janvier février mars avril mai juin juillet août septembre octobre novembre décembre)
  @months_en ~w(January February March April May June July August September October November December)

  @doc "The IMF edition as a month: « octobre 2026 », “October 2026”."
  def edition_label(%{code: <<year::binary-size(4), "-", month::binary-size(2)>>}, locale) do
    names = if locale == "fr", do: @months_fr, else: @months_en
    Enum.at(names, String.to_integer(month) - 1) <> " " <> year
  end

  def edition_label(_, _), do: "—"

  @doc """
  Typical network round trips to the server in Europe, by region, and the
  Cloudflare cities that serve the cached answers. Published orders of
  magnitude: Cloudflare (North Africa 50–100 ms, the south around 250 ms),
  OpenMetal (Lagos 90–120 ms), Hats Network (Johannesburg 163 ms).
  """
  def latency_rows(locale) do
    [
      {tr(locale, "Europe", "Europe"), "≈ 5 – 20 ms",
       tr(
         locale,
         "Un point de présence dans chaque grande ville",
         "A point of presence in every large city"
       )},
      {tr(locale, "Afrique du Nord", "North Africa"), "≈ 50 – 100 ms",
       tr(locale, "Casablanca, Alger, Tunis, Le Caire", "Casablanca, Algiers, Tunis, Cairo")},
      {tr(locale, "Afrique de l'Ouest", "West Africa"), "≈ 90 – 120 ms (Lagos)",
       "Lagos, Dakar, Abidjan"},
      {tr(locale, "Afrique de l'Est", "East Africa"),
       tr(locale, "variable, souvent via l'Europe", "varies, often through Europe"),
       tr(
         locale,
         "Nairobi, Kigali, Addis-Abeba, Dar es Salaam",
         "Nairobi, Kigali, Addis Ababa, Dar es Salaam"
       )},
      {tr(locale, "Afrique australe", "Southern Africa"), "≈ 160 – 250 ms",
       tr(
         locale,
         "Johannesburg, Le Cap, Durban, Lusaka",
         "Johannesburg, Cape Town, Durban, Lusaka"
       )}
    ]
  end

  attr :lines, :list, required: true
  attr :numbers, :boolean, default: true
  attr :label, :string, default: nil
  attr :class, :any, default: nil

  @doc "A block of coloured code, one `<li>` per line (numbers drawn by CSS)."
  def code_block(assigns) do
    ~H"""
    <div class={["code-block", @class]} role="region" aria-label={@label} tabindex="0">
      <ol class={["code-lines", !@numbers && "no-numbers"]}>{lines_html(@lines)}</ol>
    </div>
    """
  end

  @doc """
  The `<li>` of each line, built here rather than in the template: lines
  are shown with `white-space: pre`, so no space or line break may slip
  between the tokens (the HEEx formatter would add some). Text is escaped.
  """
  def lines_html(lines) do
    lines
    |> Enum.map(fn line ->
      [
        "<li>",
        Enum.map(line, fn {class, text} ->
          [
            ~s(<span class="tok-),
            class,
            ~s(">),
            Phoenix.HTML.html_escape(text) |> Phoenix.HTML.safe_to_string(),
            "</span>"
          ]
        end),
        "</li>"
      ]
    end)
    |> IO.iodata_to_binary()
    |> Phoenix.HTML.raw()
  end

  attr :route, :map, required: true
  attr :locale, :string, required: true

  @doc "The code of a route in four languages, as tabs that need no script."
  def code_tabs(assigns) do
    ~H"""
    <div class="code-card">
      <fieldset class="code-tabs">
        <legend class="sr-only">
          {tr(@locale, "Langage de l'exemple", "Language of the example")}
        </legend>
        <%= for {{lang, label, _}, i} <- Enum.with_index(@route.code) do %>
          <input
            type="radio"
            class="sr-only"
            name={"lang-" <> @route.id}
            id={"lang-#{@route.id}-#{lang}"}
            value={lang}
            checked={i == 0}
          />
          <label for={"lang-#{@route.id}-#{lang}"}>{label}</label>
        <% end %>
      </fieldset>
      <div class="code-panes">
        <div :for={{lang, label, lines} <- @route.code} class="code-pane" data-lang={lang}>
          <.code_block lines={lines} label={label} />
        </div>
      </div>
    </div>
    """
  end

  attr :perf, :map, default: nil
  attr :label, :string, required: true
  attr :class, :any, default: nil

  @doc "The hourly p95 over the day, against the budget (dashed)."
  def sparkline(assigns) do
    ~H"""
    <svg
      :if={@perf}
      class={["api-spark", @class]}
      viewBox="0 0 120 28"
      preserveAspectRatio="none"
      role="img"
      aria-label={@label}
    >
      <line x1="0" x2="120" y1={@perf.budget_y} y2={@perf.budget_y} class="api-spark-budget" />
      <polyline points={@perf.points} class="api-spark-line" />
    </svg>
    """
  end
end
