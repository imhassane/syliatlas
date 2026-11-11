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

  @extra %{
    "ecowas" => %{
      slug: %{"es" => "cedeao", "pt" => "cedeao"},
      short: %{
        "es" => "CEDEAO",
        "pt" => "CEDEAO",
        "ar" => "إيكواس",
        "hi" => "ECOWAS",
        "zh" => "西共体"
      },
      name: %{
        "es" => "Comunidad Económica de los Estados de África Occidental",
        "pt" => "Comunidade Económica dos Estados da África Ocidental",
        "ar" => "المجموعة الاقتصادية لدول غرب أفريقيا",
        "hi" => "पश्चिम अफ़्रीकी राज्यों का आर्थिक समुदाय",
        "zh" => "西非国家经济共同体"
      }
    },
    "aes" => %{
      slug: %{"es" => "aes", "pt" => "aes"},
      short: %{
        "es" => "AES",
        "pt" => "AES",
        "ar" => "تحالف دول الساحل",
        "hi" => "AES",
        "zh" => "萨赫勒国家联盟"
      },
      name: %{
        "es" => "Alianza de Estados del Sahel",
        "pt" => "Aliança dos Estados do Sahel",
        "ar" => "تحالف دول الساحل",
        "hi" => "साहेल राज्यों का गठबंधन",
        "zh" => "萨赫勒国家联盟"
      }
    },
    "waemu" => %{
      slug: %{"es" => "uemoa", "pt" => "uemoa"},
      short: %{
        "es" => "UEMOA",
        "pt" => "UEMOA",
        "ar" => "الاتحاد الاقتصادي والنقدي لغرب أفريقيا",
        "hi" => "WAEMU",
        "zh" => "西非经货联盟"
      },
      name: %{
        "es" => "Unión Económica y Monetaria de África Occidental",
        "pt" => "União Económica e Monetária Oeste-Africana",
        "ar" => "الاتحاد الاقتصادي والنقدي لغرب أفريقيا",
        "hi" => "पश्चिम अफ़्रीकी आर्थिक और मौद्रिक संघ",
        "zh" => "西非经济货币联盟"
      }
    },
    "cemac" => %{
      slug: %{"es" => "cemac", "pt" => "cemac"},
      short: %{
        "es" => "CEMAC",
        "pt" => "CEMAC",
        "ar" => "الجماعة الاقتصادية والنقدية لوسط أفريقيا",
        "hi" => "CEMAC",
        "zh" => "中部非洲经货共同体"
      },
      name: %{
        "es" => "Comunidad Económica y Monetaria de África Central",
        "pt" => "Comunidade Económica e Monetária da África Central",
        "ar" => "الجماعة الاقتصادية والنقدية لوسط أفريقيا",
        "hi" => "मध्य अफ़्रीका का आर्थिक और मौद्रिक समुदाय",
        "zh" => "中部非洲经济货币共同体"
      }
    },
    "eac" => %{
      slug: %{"es" => "cae", "pt" => "cao"},
      short: %{
        "es" => "CAE",
        "pt" => "CAO",
        "ar" => "مجموعة شرق أفريقيا",
        "hi" => "EAC",
        "zh" => "东非共同体"
      },
      name: %{
        "es" => "Comunidad de África Oriental",
        "pt" => "Comunidade da África Oriental",
        "ar" => "مجموعة شرق أفريقيا",
        "hi" => "पूर्वी अफ़्रीकी समुदाय",
        "zh" => "东非共同体"
      }
    },
    "sadc" => %{
      slug: %{"es" => "sadc", "pt" => "sadc"},
      short: %{"es" => "SADC", "pt" => "SADC", "ar" => "سادك", "hi" => "SADC", "zh" => "南共体"},
      name: %{
        "es" => "Comunidad de Desarrollo de África Austral",
        "pt" => "Comunidade de Desenvolvimento da África Austral",
        "ar" => "مجموعة تنمية الجنوب الأفريقي",
        "hi" => "दक्षिणी अफ़्रीकी विकास समुदाय",
        "zh" => "南部非洲发展共同体"
      }
    }
  }

  # Names in the other languages of the site; Arabic, Hindi and Chinese
  # pages use the English slugs.
  @communities (for c <- @communities do
                  extra = Map.fetch!(@extra, c.code)

                  %{
                    c
                    | slug:
                        Map.merge(c.slug, extra.slug)
                        |> then(
                          &Map.merge(%{"ar" => &1["en"], "hi" => &1["en"], "zh" => &1["en"]}, &1)
                        ),
                      short: Map.merge(c.short, extra.short),
                      name: Map.merge(c.name, extra.name)
                  }
                end)

  def all, do: @communities
  def as_of, do: @as_of
  def get(code), do: Enum.find(@communities, &(&1.code == code))

  def by_slug(slug, locale),
    do: Enum.find(@communities, &(SyliAtlas.Locales.pick(&1.slug, locale) == slug))

  @doc "The communities a country belongs to."
  def for_country(code), do: Enum.filter(@communities, &(code in &1.members))
end
