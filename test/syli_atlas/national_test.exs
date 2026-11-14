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

  describe "the bundled Ethiopian rebasing" do
    test "is shown, being checked, and not counted in the sum" do
      doc = National.document()
      eth = National.for_country(doc, "ETH")
      fig = National.figure(eth, "gdp_usd_bn", 2025)

      assert fig["value"] == 201.42
      assert fig["status"] == "pending_review"
      refute fig["counted"]
      assert fig["imf"] > 120 and fig["imf"] < 130
      assert fig["gap_pct"] > 50
      assert fig["per_capita"] > 1700
      assert eth["rebasing"]["active"]
      assert eth["rebasing"]["new_base"] == "2024/25"

      africa = National.africa(doc, 2025)
      assert africa["national_total"] == africa["imf_total"]
      assert africa["counted"] == 0
      assert africa["pending"] == ["ETH"]
      assert africa["missing"] == ["ERI"]
      assert_in_delta africa["after_review_total"] - africa["imf_total"], 201.42 - fig["imf"], 0.2
    end

    test "once a person verifies it, it counts; rejected, it leaves the pages" do
      figure = National.get("ETH", "gdp_usd_bn", 2025)
      National.verify!(figure, "admin@test")

      doc = National.document()
      africa = National.africa(doc, 2025)
      assert africa["counted"] == 1
      assert africa["pending"] == []
      assert africa["national_total"] > africa["imf_total"]
      assert Enum.find(africa["rows"], &(&1["code"] == "ETH"))["source"] == "national"

      National.reject!(National.get!(figure.id), "admin@test")
      doc = National.document()
      assert National.figure(National.for_country(doc, "ETH"), "gdp_usd_bn", 2025) == nil
      assert National.africa(doc, 2025)["counted"] == 0
    end

    test "a reviewed figure is not overwritten by the bundled file" do
      figure = National.get("ETH", "gdp_usd_bn", 2025)
      National.verify!(figure, "admin@test")
      National.seed!()
      assert National.get("ETH", "gdp_usd_bn", 2025).status == "verified"
    end
  end
end
