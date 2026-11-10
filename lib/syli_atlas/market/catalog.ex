defmodule SyliAtlas.Market.Catalog do
  @moduledoc """
  Market data sources and what their licence lets us do. Licences are data,
  applied by the code: a value is shown on a public page only when the
  licence of the source it came from allows it (or while the market pages
  are in preview, see `SyliAtlas.Market.public?/0`).
  """

  @sources %{
    "mansa" => %{
      code: "mansa",
      name: "Mansa Markets",
      url: "https://mansamarkets.com",
      kind: "aggregator",
      status: "active",
      # Free tier: 100 requests a day, personal use only.
      licence: %{
        display_public: false,
        export_csv: false,
        redistribute_api: false,
        attribution: "Mansa Markets"
      },
      daily_quota: 100,
      daily_cap: 95
    },
    "brvm_boc" => %{
      code: "brvm_boc",
      name: "BRVM – Bulletin officiel de la cote",
      url: "https://www.brvm.org",
      kind: "official",
      status: "planned",
      licence: %{
        display_public: false,
        export_csv: false,
        redistribute_api: false,
        attribution: "BRVM"
      },
      daily_quota: nil,
      daily_cap: nil
    },
    "ngx_daily" => %{
      code: "ngx_daily",
      name: "NGX – Daily price list",
      url: "https://ngxgroup.com",
      kind: "official",
      status: "planned",
      licence: %{
        display_public: false,
        export_csv: false,
        redistribute_api: false,
        attribution: "Nigerian Exchange Group"
      },
      daily_quota: nil,
      daily_cap: nil
    }
  }

  def all, do: @sources |> Map.values() |> Enum.sort_by(&(&1.status != "active"))
  def get(code), do: Map.get(@sources, code)
  def get!(code), do: Map.fetch!(@sources, code)

  def name(code), do: (get(code) || %{name: code}).name
  def url(code), do: (get(code) || %{url: nil}).url

  @doc "May values of this source appear on public pages?"
  def display_public?(code), do: match?(%{licence: %{display_public: true}}, get(code))
end
