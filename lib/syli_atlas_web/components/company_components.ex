defmodule SyliAtlasWeb.CompanyComponents do
  @moduledoc """
  The companies of a product page (SyliAtlas.Companies): only those their
  source confirmed, each with its source and the date of the last check.
  """
  use Phoenix.Component
  use Gettext, backend: SyliAtlasWeb.Gettext

  import SyliAtlasWeb.AfricaTradeComponents, only: [country: 1]

  def kind_label("mine"), do: gettext("Mine")
  def kind_label("producer"), do: gettext("Producer")
  def kind_label("state_company"), do: gettext("State company")
  def kind_label("holding"), do: gettext("Investment holding")
  def kind_label("refinery"), do: gettext("Refinery")
  def kind_label(other), do: other

  attr :companies, :list, required: true
  attr :countries, :map, required: true
  attr :locale, :string, required: true

  def table(assigns) do
    ~H"""
    <div class="card market-table" id="companies">
      <div class="table-box">
        <table class="table table-stack market-list" id="companies-table">
          <caption class="vh">{gettext("The main companies of the sector")}</caption>
          <thead>
            <tr>
              <th scope="col" class="l">{gettext("Company or mine")}</th>
              <th scope="col" class="l">{gettext("Country")}</th>
              <th scope="col" class="l">{gettext("Activity and owners")}</th>
              <th scope="col" class="l">{gettext("Source")}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={c <- @companies} id={"company-#{c.id}"}>
              <th scope="row" class="l">{c.name}</th>
              <td class="l" data-label={gettext("Country")}>
                <.country code={c.country} countries={@countries} locale={@locale} />
              </td>
              <td class="l" data-label={gettext("Activity and owners")}>
                {kind_label(c.kind)}<span :if={c.owners}> · {c.owners}</span>
                <span :if={c.listing} class="small muted"> · {gettext("listed:")} {c.listing}</span>
              </td>
              <td class="l" data-label={gettext("Source")}>
                <a href={c.source_url} rel="noopener nofollow">{c.source_name}</a>
                <span class="small subtle">
                  · {gettext("checked on %{date}",
                    date:
                      SyliAtlasWeb.RatingComponents.date_text(
                        c.verified_at && DateTime.to_date(c.verified_at) |> Date.to_iso8601(),
                        @locale
                      )
                  )}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p class="src card-foot">
        {gettext(
          "Not from BACI: a list kept by Syli Atlas from the companies' own pages. Every month each line is read again against its source by an AI under strict rules (a sentence of the page copied word for word, the company, the product, the country and the owners named); a line that is not confirmed is withdrawn at once."
        )}
      </p>
    </div>
    """
  end
end
