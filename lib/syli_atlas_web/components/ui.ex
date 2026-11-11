defmodule SyliAtlasWeb.UI do
  @moduledoc """
  Generic Sily building blocks used by every public page: sections, cards,
  stat tiles, ranked lists, question cards, FAQ. They hold no domain logic;
  domain helpers live in `SyliAtlasWeb.PageComponents`.
  """
  use Phoenix.Component

  # Sections ------------------------------------------------------------

  attr :variant, :string, default: "plain", values: ~w(plain alt deep)

  attr :tight, :atom,
    default: nil,
    values: [nil, :top, :bottom],
    doc: "drop the top or bottom padding"

  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def section(assigns) do
    ~H"""
    <section
      class={[
        "section",
        @variant == "alt" && "section-alt",
        @variant == "deep" && "section-deep",
        @tight == :top && "tight-top",
        @tight == :bottom && "tight-bottom",
        @class
      ]}
      {@rest}
    >
      <div class="wrap stack gap-6">{render_slot(@inner_block)}</div>
    </section>
    """
  end

  attr :eyebrow, :string, default: nil
  attr :title, :string, required: true
  attr :level, :integer, default: 2, values: [1, 2]
  attr :size, :string, default: "h1", values: ~w(display h1 h2)
  slot :intro
  slot :actions

  def section_head(assigns) do
    ~H"""
    <div class="head-row">
      <div class="section-head">
        <p :if={@eyebrow} class="eyebrow">{@eyebrow}</p>
        <h1 :if={@level == 1} class={@size}>{@title}</h1>
        <h2 :if={@level == 2} class={@size}>{@title}</h2>
        <p :for={intro <- @intro} class="lead">{render_slot(intro)}</p>
      </div>
      <div :if={@actions != []} class="head-actions">{render_slot(@actions)}</div>
    </div>
    """
  end

  # Cards ---------------------------------------------------------------

  attr :class, :any, default: nil
  attr :pad, :boolean, default: false
  attr :rest, :global
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <div class={["card", @pad && "pad", @class]} {@rest}>{render_slot(@inner_block)}</div>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :eyebrow, :string, default: nil
  slot :actions

  def card_head(assigns) do
    ~H"""
    <div class="card-head">
      <div>
        <p :if={@eyebrow} class="eyebrow">{@eyebrow}</p>
        <h2 class="h2">{@title}</h2>
        <p :if={@subtitle} class="small muted">{@subtitle}</p>
      </div>
      <div :if={@actions != []}>{render_slot(@actions)}</div>
    </div>
    """
  end

  slot :inner_block, required: true

  def card_foot(assigns) do
    ~H"""
    <p class="card-foot src">{render_slot(@inner_block)}</p>
    """
  end

  # Figures -------------------------------------------------------------

  slot :stat, required: true do
    attr :label, :string, required: true
    attr :value, :string, required: true
    attr :tone, :string
    attr :id, :string
  end

  attr :class, :any, default: nil

  @doc "A row of key figures. Each stat's inner block is its note line."
  def stat_grid(assigns) do
    ~H"""
    <dl class={["stats", @class]}>
      <div :for={s <- @stat}>
        <dt>{s.label}</dt>
        <dd class={["big", s[:tone]]} data-kpi={s[:id]}>{s.value}</dd>
        <dd class="small muted">{render_slot(s)}</dd>
      </div>
    </dl>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :tone, :string, default: nil

  def list_row(assigns) do
    ~H"""
    <div class="list-row"><span>{@label}</span><b class={["num", @tone]}>{@value}</b></div>
    """
  end

  attr :items, :list,
    required: true,
    doc: "maps with :key, :name, :href, :value, optional :tone, :bar, :neg"

  attr :current, :string, default: nil
  attr :bars, :boolean, default: false
  attr :start, :integer, default: 0, doc: "rank of the first item minus one (paged lists)"

  @doc "Numbered ranking. With `bars`, each row shows a bar scaled by `:bar` (0–100)."
  def rank_list(assigns) do
    ~H"""
    <ol class={["rank-list", @bars && "rank-bars"]} start={@start + 1}>
      <li
        :for={{item, i} <- Enum.with_index(@items, @start + 1)}
        class={item.key == @current && "is-current"}
      >
        <span class="num subtle">{i}</span>
        <a href={item.href}>{item.name}</a>
        <span :if={@bars} class="bar-track" aria-hidden="true">
          <span class={["bar-fill", item[:neg] && "neg"]} style={"width: #{item[:bar] || 0}%"}></span>
        </span>
        <b class={["num", item[:tone]]}>{item.value}</b>
      </li>
    </ol>
    """
  end

  attr :pct, :integer, required: true
  attr :neg, :boolean, default: false

  def bar(assigns) do
    ~H"""
    <span class="bar-track" aria-hidden="true"><span
      class={["bar-fill", @neg && "neg"]}
      style={"width: #{@pct}%"}
    ></span></span>
    """
  end

  # Navigation blocks ---------------------------------------------------

  attr :href, :string, required: true
  attr :eyebrow, :string, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :cta, :string, required: true
  slot :inner_block, required: true

  def question_card(assigns) do
    ~H"""
    <a class="card qcard" href={@href}>
      <span class="eyebrow">{@eyebrow}</span>
      <span class="h2">{@title}</span>
      <span class="muted">{@subtitle}</span>
      <div>{render_slot(@inner_block)}</div>
      <span class="qcard-cta">{@cta} →</span>
    </a>
    """
  end

  attr :n, :string, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  def feature(assigns) do
    ~H"""
    <div class="feature">
      <span class="n">{@n}</span>
      <h3 class="h2">{@title}</h3>
      <p>{render_slot(@inner_block)}</p>
    </div>
    """
  end

  attr :items, :list, required: true, doc: "{question, answer} tuples"

  def faq(assigns) do
    ~H"""
    <div class="faq-list">
      <details :for={{q, a} <- @items} class="faq">
        <summary>{q}</summary>
        <p>{a}</p>
      </details>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :color, :string, required: true, doc: "CSS variable name, e.g. --c1"
  attr :remove_href, :string, default: nil
  attr :remove_label, :string, default: nil

  def series_chip(assigns) do
    ~H"""
    <span class="chip chip-series" style={"--dot: var(#{@color})"}>
      <i aria-hidden="true"></i>{@name}
      <a :if={@remove_href} href={@remove_href} aria-label={@remove_label}>×</a>
    </span>
    """
  end

  attr :label, :string, required: true
  attr :class, :any, default: nil
  slot :inner_block, required: true

  @doc "A labelled form field stacked over its control."
  def field(assigns) do
    ~H"""
    <label class={["field", @class]}>
      <span class="eyebrow">{@label}</span>
      {render_slot(@inner_block)}
    </label>
    """
  end

  attr :name, :string, required: true
  attr :options, :list, required: true, doc: "{value, label} tuples"
  attr :selected, :any, default: nil
  attr :rest, :global

  def select(assigns) do
    ~H"""
    <select name={@name} class="select" {@rest}>
      <option :for={{v, l} <- @options} value={v} selected={to_string(v) == to_string(@selected)}>
        {l}
      </option>
    </select>
    """
  end

  # Filters ---------------------------------------------------------------

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :summary, :string, default: nil, doc: "current choice, shown on the phone's button"
  slot :inner_block, required: true

  @doc """
  Filters that sit inline from 40rem and, on phones, open in a bottom sheet
  from a button showing the current choice. The sheet is a native popover
  (Escape and a tap outside close it) that can be dragged down to close
  (`assets/js/sheet.js`). The form inside keeps its own submit button,
  shown full width at the bottom of the sheet.
  """
  def filter_sheet(assigns) do
    ~H"""
    <div class="sheet-bar">
      <button type="button" class="sheet-trigger" popovertarget={@id} aria-haspopup="dialog">
        <svg
          width="18"
          height="18"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="1.8"
          stroke-linecap="round"
          aria-hidden="true"
        ><path d="M4 6h10M18 6h2M4 12h4M12 12h8M4 18h12M20 18h0"></path><circle cx="16" cy="6" r="2">
        </circle><circle cx="10" cy="12" r="2"></circle><circle cx="18" cy="18" r="2"></circle></svg>
        <span class="sheet-trigger-label">{@title}</span>
        <span :if={@summary} class="sheet-trigger-summary">{@summary}</span>
      </button>
    </div>
    <div id={@id} popover class="sheet" role="dialog" aria-label={@title}>
      <div class="sheet-head">
        <span class="sheet-handle" aria-hidden="true"></span>
        <p class="h2">{@title}</p>
      </div>
      {render_slot(@inner_block)}
    </div>
    """
  end

  # Tables ----------------------------------------------------------------

  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :caption, :string, required: true, doc: "names the table for screen readers"
  attr :current, :any, default: nil, doc: "row (as given) to highlight"
  attr :wide, :boolean, default: false, doc: "many columns: stack below 60rem instead of 34rem"

  slot :head, required: true, doc: "the row header (first column)" do
    attr :label, :string, required: true
  end

  slot :col do
    attr :label, :string, required: true
    attr :class, :any
  end

  @doc """
  A data table that never scrolls sideways: in a narrow container (phone,
  side column) each row becomes a card, its header on top and every value
  labelled (`data-label`, read by CSS). Sized by container queries, so it
  adapts to where it sits rather than to the screen.
  """
  def data_table(assigns) do
    ~H"""
    <div class="table-box" role="region" aria-labelledby={"#{@id}-caption"}>
      <table id={@id} class={["table table-stack", @wide && "table-wide"]}>
        <caption id={"#{@id}-caption"} class="vh">{@caption}</caption>
        <thead>
          <tr>
            <th scope="col">{hd(@head).label}</th>
            <th :for={col <- @col} scope="col" class={col[:class]}>{col.label}</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @rows} class={row == @current && "is-current"}>
            <th scope="row">{render_slot(@head, row)}</th>
            <td :for={col <- @col} data-label={col.label} class={col[:class]}>
              {render_slot(col, row)}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  # Pagination ------------------------------------------------------------

  attr :page, SyliAtlasWeb.Pagination, required: true
  attr :href, :any, required: true, doc: "function from a page number to its URL"
  attr :label, :string, required: true, doc: "names the navigation for screen readers"
  attr :prev_label, :string, required: true
  attr :next_label, :string, required: true
  attr :summary, :string, default: nil, doc: "e.g. « 11–20 of 54 »"

  @doc "Previous, numbered and next links. Renders nothing for a single page."
  def pagination(assigns) do
    ~H"""
    <nav :if={@page.pages > 1} class="pager" aria-label={@label}>
      <span :if={@summary} class="pager-summary">{@summary}</span>
      <ol>
        <li>
          <a :if={@page.page > 1} class="pager-step" href={@href.(@page.page - 1)} rel="prev">
            <span aria-hidden="true">←</span><span class="pager-step-label">{@prev_label}</span>
          </a>
        </li>
        <li :for={n <- SyliAtlasWeb.Pagination.window(@page)} class="pager-num">
          <span :if={n == :gap} class="pager-gap" aria-hidden="true">…</span>
          <a :if={n != :gap} href={@href.(n)} aria-current={n == @page.page && "page"}>{n}</a>
        </li>
        <li>
          <a
            :if={@page.page < @page.pages}
            class="pager-step"
            href={@href.(@page.page + 1)}
            rel="next"
          >
            <span class="pager-step-label">{@next_label}</span><span aria-hidden="true">→</span>
          </a>
        </li>
      </ol>
    </nav>
    """
  end
end
