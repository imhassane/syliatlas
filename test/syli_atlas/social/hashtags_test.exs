defmodule SyliAtlas.Social.HashtagsTest do
  use SyliAtlas.DataCase, async: true

  alias SyliAtlas.Social.Hashtags

  @link "https://syliatlas.com/en/x?utm_source=x&utm_medium=social"

  test "X: country and subject close the first paragraph; LinkedIn: tags last" do
    attrs =
      Hashtags.add(%{
        kind: "rating",
        area_code: "CIV",
        key: "rating:CIV:sp:2026-11-01",
        text_x: "S&P upgrades Nigeria to B.\n\nRatings, with the full history:",
        text_linkedin: "S&P relève la note du Nigeria.\n\nSource : communiqué de S&P.",
        link_x: @link
      })

    assert attrs.text_x ==
             "S&P upgrades Nigeria to B. #IvoryCoast #CreditRating\n\nRatings, with the full history:"

    assert attrs.text_linkedin ==
             "S&P relève la note du Nigeria.\n\nSource : communiqué de S&P.\n\n#CôteDIvoire #NotationSouveraine #Finance #Afrique"
  end

  test "a list keeps its tags on their own line; no country for an IMF edition" do
    attrs =
      Hashtags.add(%{
        kind: "edition",
        key: "edition:1",
        text_x: "New IMF forecasts\n1. A 7%\n2. B 6%\n\nAll 54 countries:",
        text_linkedin: "Le FMI publie.",
        link_x: @link
      })

    assert attrs.text_x ==
             "New IMF forecasts\n1. A 7%\n2. B 6%\n#IMF #Africa\n\nAll 54 countries:"

    assert attrs.text_linkedin == "Le FMI publie.\n\n#FMI #Croissance #Économie #Afrique"
  end

  test "X never goes over 280 characters" do
    long = String.duplicate("a", 250)

    attrs =
      Hashtags.add(%{
        kind: "rating",
        area_code: "CIV",
        text_x: long,
        text_linkedin: "x",
        link_x: @link
      })

    assert attrs.text_x == long
  end

  test "debt figures and short country names" do
    attrs = %{kind: "national", area_code: "COD", key: "national:COD:public_debt_pct_gdp:2025:1"}

    assert Hashtags.tags(attrs, "fr") ==
             ["#RDC", "#DettePublique", "#FinancesPubliques", "#Afrique"]

    assert Hashtags.tags(attrs, "en") == ["#DRC", "#PublicDebt"]
  end
end
