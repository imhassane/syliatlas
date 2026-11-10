defmodule SyliAtlas.Economy.Communities do
  @moduledoc """
  African regional economic communities and monetary unions, with their
  members as of 10 November 2026. A country can belong to several (the DR
  Congo and Tanzania are in both the EAC and SADC).

  Burkina Faso, Mali and Niger left ECOWAS in January 2025 and formed the
  Alliance of Sahel States (AES); Guinea, suspended, is still a member.
  Membership is reference data, checked by hand when it changes.
  """

  @communities [
    %{
      code: "ecowas",
      slug: %{"fr" => "cedeao", "en" => "ecowas"},
      short: %{"fr" => "CEDEAO", "en" => "ECOWAS"},
      name: %{
        "fr" => "Communauté économique des États de l'Afrique de l'Ouest",
        "en" => "Economic Community of West African States"
      },
      kind: "community",
      members: ~w(BEN CPV CIV GMB GHA GIN GNB LBR NGA SEN SLE TGO)
    },
    %{
      code: "aes",
      slug: %{"fr" => "aes", "en" => "aes"},
      short: %{"fr" => "AES", "en" => "AES"},
      name: %{"fr" => "Alliance des États du Sahel", "en" => "Alliance of Sahel States"},
      kind: "community",
      members: ~w(BFA MLI NER)
    },
    %{
      code: "waemu",
      slug: %{"fr" => "uemoa", "en" => "waemu"},
      short: %{"fr" => "UEMOA", "en" => "WAEMU"},
      name: %{
        "fr" => "Union économique et monétaire ouest-africaine",
        "en" => "West African Economic and Monetary Union"
      },
      kind: "monetary_union",
      zone: "uemoa",
      members: ~w(BEN BFA CIV GNB MLI NER SEN TGO)
    },
    %{
      code: "cemac",
      slug: %{"fr" => "cemac", "en" => "cemac"},
      short: %{"fr" => "CEMAC", "en" => "CEMAC"},
      name: %{
        "fr" => "Communauté économique et monétaire de l'Afrique centrale",
        "en" => "Economic and Monetary Community of Central Africa"
      },
      kind: "monetary_union",
      zone: "cemac",
      members: ~w(CMR CAF TCD COG GNQ GAB)
    },
    %{
      code: "eac",
      slug: %{"fr" => "eac", "en" => "eac"},
      short: %{"fr" => "EAC", "en" => "EAC"},
      name: %{"fr" => "Communauté d'Afrique de l'Est", "en" => "East African Community"},
      kind: "community",
      members: ~w(BDI COD KEN RWA SOM SSD TZA UGA)
    },
    %{
      code: "sadc",
      slug: %{"fr" => "sadc", "en" => "sadc"},
      short: %{"fr" => "SADC", "en" => "SADC"},
      name: %{
        "fr" => "Communauté de développement de l'Afrique australe",
        "en" => "Southern African Development Community"
      },
      kind: "community",
      members: ~w(AGO BWA COM COD SWZ LSO MDG MWI MUS MOZ NAM SYC ZAF TZA ZMB ZWE)
    }
  ]

  @as_of "2026-11-10"

  def all, do: @communities
  def as_of, do: @as_of
  def get(code), do: Enum.find(@communities, &(&1.code == code))

  def by_slug(slug, locale), do: Enum.find(@communities, &(&1.slug[locale] == slug))

  @doc "The communities a country belongs to."
  def for_country(code), do: Enum.filter(@communities, &(code in &1.members))
end
