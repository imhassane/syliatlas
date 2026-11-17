defmodule SyliAtlas.NationalTest do
  @moduledoc """
  National figures: the automatic checks, the « being checked » status for
  exceptions, the review by a person, and the sum of national figures for
  Africa with the IMF as fallback.
  """
  use SyliAtlas.DataCase, async: false

  alias SyliAtlas.National
  alias SyliAtlas.National.Verify

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    :ok
  end

  describe "Verify" do
    @doc_text """
    The revised national accounts put GDP for the 2024/25 fiscal year at
    24.03 trillion birr, equivalent to US$201.42 billion.
    """

    @attrs %{
      "country_code" => "ETH",
      "indicator" => "gdp_usd_bn",
      "calendar_year" => 2025,
      "period_label" => "2024/25",
      "value" => "201.42",
      "value_lcu" => "24030000000000",
      "currency" => "ETB",
      "fx_rate" => "119.30",
      "source_url" => "https://www.mopd.gov.et/rebasing.pdf",
      "quote" => "GDP for the 2024/25 fiscal year at 24.03 trillion birr"
    }

    @ctx %{
      document: @doc_text,
      second_read: %{
        "value" => "201.42",
        "period_label" => "2024/25",
        "indicator" => "gdp_usd_bn",
        "currency" => "ETB"
      },
      imf: 190.0,
      domains: ["mopd.gov.et"],
      known_country?: true
    }

    test "every check passed: published at once" do
      assert {"auto_verified", checks} = Verify.run(@attrs, @ctx)
      assert checks["gap_pct"] == 6.0
    end

    test "a gap of more than 15 % with the IMF goes to a person" do
      assert {"pending_review", checks} = Verify.run(@attrs, %{@ctx | imf: 126.4})
      assert checks["gap_vs_imf"] == false
      assert checks["gap_pct"] == 59.4
    end

    test "a newspaper is not an official source" do
      attrs = %{@attrs | "source_url" => "https://www.businessday.co.za/ethiopia"}
      assert {"pending_review", %{"official_source" => false}} = Verify.run(attrs, @ctx)
      assert Verify.official_source?("https://stats.mopd.gov.et/x", ["mopd.gov.et"])
      refute Verify.official_source?("https://mopd.gov.et.evil.com/x", ["mopd.gov.et"])
      refute Verify.official_source?("http://mopd.gov.et/x", ["mopd.gov.et"])
    end

    test "the quote must be in the document and hold the figure" do
      refute Verify.in_document?("GDP of 99 trillion birr", @doc_text, 201.42, "24030000000000")

      refute Verify.in_document?(
               "GDP for the 2024/25 fiscal year",
               @doc_text,
               201.42,
               "24030000000000"
             )

      assert Verify.in_document?("US$201.42 billion", @doc_text, 201.42, nil)

      assert {"pending_review", %{"in_document" => false}} =
               Verify.run(@attrs, %{@ctx | document: nil})
    end

    test "two extractions must agree" do
      second = %{@ctx.second_read | "value" => "201.4"}

      assert {"pending_review", %{"two_reads" => false}} =
               Verify.run(@attrs, %{@ctx | second_read: second})
    end

    test "local currency over the rate must give the dollar amount" do
      attrs = %{@attrs | "fx_rate" => "90"}
      assert {"pending_review", %{"arithmetic" => false}} = Verify.run(attrs, @ctx)
    end

    test "the first figure of a country goes to a person" do
      assert {"pending_review", %{"known_country" => false}} =
               Verify.run(@attrs, %{@ctx | known_country?: false})
    end

    test "numbers are read whatever the separators" do
      assert Verify.numbers("24,03 billions et 1,234.5 puis 201 420") == [
               24.03,
               1234.5,
               201_420.0
             ]
    end
  end

  describe "the bundled figures (15 countries followed)" do
    test "South Africa: shown, being checked, and not counted in the sum" do
      doc = National.document()
      zaf = National.for_country(doc, "ZAF")
      fig = National.figure(zaf, "gdp_usd_bn", 2025)

      assert fig["value"] == 449.74
      assert fig["status"] == "pending_review"
      refute fig["counted"]
      assert fig["imf"] > 420 and fig["imf"] < 435
      assert fig["per_capita"] > 6000
      assert zaf["rebasing"]["active"]
      assert zaf["rebasing"]["new_base"] == "2022"

      africa = National.africa(doc, 2025)
      assert africa["national_total"] == africa["imf_total"]
      assert africa["counted"] == 0
      # The followed countries, all waiting for a person.
      assert africa["pending"] == National.tracked()

      assert africa["missing"] == ["ERI"]
      assert africa["after_review_total"] - africa["imf_total"] > 449.74 - fig["imf"]
    end

    test "only the followed countries keep figures, even reviewed ones" do
      assert National.tracked() ==
               ~w(CMR DZA EGY GHA KEN MAR MUS NAM NGA RWA SEN TZA UGA ZAF ZWE)

      # A figure of a country no longer followed (Ethiopia: the rebasing
      # alert covers it) leaves at the next start.
      National.submit!(%{
        "country_code" => "ETH",
        "indicator" => "gdp_usd_bn",
        "calendar_year" => 2025,
        "period_label" => "2024/25",
        "value" => "201.42",
        "source_name" => "Ministère",
        "source_url" => "https://mopd.gov.et/x",
        "status" => "pending_review"
      })

      National.verify!(National.get("ETH", "gdp_usd_bn", 2025), "admin@test")
      National.seed!()
      refute National.get("ETH", "gdp_usd_bn", 2025)
      refute National.for_country(National.document(), "ETH")
      # Its rebasing alert stays.
      assert National.rebasing(National.document(), "ETH")["active"]
    end

    test "a confirmed figure prepares its post for X and LinkedIn, once per value" do
      figure = National.get("ZAF", "gdp_usd_bn", 2025)
      National.verify!(figure, "admin@test")
      National.verify!(figure, "admin@test")

      assert [post] = SyliAtlas.Social.drafts()
      assert post.kind == "national"
      assert post.key == "national:ZAF:gdp_usd_bn:2025:449.74"

      assert post.text_x =~
               "South Africa's official GDP for 2025: $450 billion (8,044 billion ZAR), according to Stats SA."

      assert post.text_linkedin =~
               "PIB officiel de l'Afrique du Sud pour 2025 : 450 milliards de dollars"

      assert post.link_x =~ "/en/countries/south-africa/economy?utm_source=x"
      assert SyliAtlas.Social.Post.x_length(post) <= 280
    end

    test "once a person verifies it, it counts; rejected, it leaves the pages" do
      figure = National.get("ZAF", "gdp_usd_bn", 2025)
      National.verify!(figure, "admin@test")

      doc = National.document()
      africa = National.africa(doc, 2025)
      assert africa["counted"] == 1
      refute "ZAF" in africa["pending"]
      assert africa["national_total"] > africa["imf_total"]
      assert Enum.find(africa["rows"], &(&1["code"] == "ZAF"))["source"] == "national"

      National.reject!(National.get!(figure.id), "admin@test")
      doc = National.document()
      assert National.figure(National.for_country(doc, "ZAF"), "gdp_usd_bn", 2025) == nil
      assert National.africa(doc, 2025)["counted"] == 0
    end

    test "Egypt's fiscal years; local amount over the rate; gaps with the IMF" do
      doc = National.document()
      egy = National.for_country(doc, "EGY")
      assert National.figure(egy, "gdp_usd_bn", 2025)["period"] == "2024/25"
      assert National.figure(egy, "gdp_usd_bn", 2026)["period"] == "2025/26"

      # Every bundled figure: local amount ÷ rate = dollars.
      for f <- National.bundled()["figures"], f["indicator"] == "gdp_usd_bn", f["value_lcu"] do
        lcu = String.to_float(f["value_lcu"] <> ".0")

        assert_in_delta lcu / String.to_float(f["fx_rate"]) / 1.0e9,
                        String.to_float(f["value"]),
                        0.01
      end

      for code <- ~w(ZAF EGY NGA DZA MAR KEN) do
        assert abs(
                 National.figure(National.for_country(doc, code), "gdp_usd_bn", 2025)["gap_pct"]
               ) < 6
      end

      # Within 15 % of the IMF, except Senegal, rebased in 2025 (+13.5 %).
      for code <- ~w(GHA TZA UGA ZWE RWA CMR NAM MUS) do
        gap = National.figure(National.for_country(doc, code), "gdp_usd_bn", 2025)["gap_pct"]
        assert abs(gap) < 15, "#{code}: #{gap}"
      end

      assert National.figure(National.for_country(doc, "SEN"), "gdp_usd_bn", 2025)["gap_pct"] > 15
    end

    test "a reviewed figure is not overwritten by the bundled file" do
      figure = National.get("ZAF", "gdp_usd_bn", 2025)
      National.verify!(figure, "admin@test")
      National.seed!()
      assert National.get("ZAF", "gdp_usd_bn", 2025).status == "verified"
    end
  end
end
