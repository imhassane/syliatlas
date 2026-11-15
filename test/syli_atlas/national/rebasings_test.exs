defmodule SyliAtlas.National.RebasingsTest do
  @moduledoc """
  Rebasing alerts: the bundled ones, proposals and their review, and the
  alert closing by itself once an IMF edition takes the rebasing in.
  """
  use SyliAtlas.DataCase, async: false

  alias SyliAtlas.{National, Repo}
  alias SyliAtlas.National.{Rebasing, Rebasings}

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    :ok
  end

  test "the bundled rebasings are online, stamped with the IMF of the day" do
    codes = Rebasings.published() |> Enum.map(& &1.country_code) |> Enum.sort()
    assert codes == ~w(ETH MUS SEN TZA ZAF)

    eth = Enum.find(Rebasings.published(), &(&1.country_code == "ETH"))
    assert eth.reference_year == 2025
    assert eth.imf_edition == Rebasings.current_edition()
    assert_in_delta String.to_float(eth.imf_before), 126.4, 0.5

    sen = National.rebasing(National.document(), "SEN")
    assert sen["active"]
    assert sen["reference_year"] == 2021
    assert sen["level_change_pct"] == 13.5
    # Any country, with or without official figures: the list of the page.
    assert length(National.rebasing_list(National.document())) == 5
  end

  test "the next edition of the IMF's outlook: April or October" do
    assert Rebasings.next_imf_edition(~D[2026-11-15]) == {2027, 4}
    assert Rebasings.next_imf_edition(~D[2027-02-01]) == {2027, 4}
    assert Rebasings.next_imf_edition(~D[2027-04-20]) == {2027, 10}
    assert Rebasings.edition_month("2026-10") == {2026, 10}
  end

  test "a proposal is completed and published by a person; a duplicate is dropped" do
    {:ok, p} =
      Rebasings.propose(%{
        "country_code" => "GHA",
        "announced_on" => "2026-11-10",
        "new_base" => "2023",
        "origin" => "watch",
        "article_url" => "https://news.test/gha",
        "excerpt" => "Ghana's statistical service rebased its GDP to 2023."
      })

    assert p.status == "proposed"
    refute National.rebasing(National.document(), "GHA")

    assert :duplicate ==
             Rebasings.propose(%{
               "country_code" => "GHA",
               "announced_on" => "2026-11-12",
               "new_base" => "2023"
             })

    # Missing fields: refused, still proposed.
    assert {:error, _} = Rebasings.publish(p, %{}, "admin@test")

    {:ok, r} =
      Rebasings.publish(
        p,
        %{
          "old_base" => "2013",
          "level_change_pct" => "+24,5 %",
          "source_name" => "Ghana Statistical Service",
          "source_url" => "https://statsghana.gov.gh/rebasing"
        },
        "admin@test"
      )

    assert r.status == "published"
    assert r.level_change_pct == "24.5"
    assert r.reference_year == 2025
    assert r.imf_before
    assert r.reviewed_by == "admin@test"

    n = National.rebasing(National.document(), "GHA")
    assert n["active"] and n["level_change_pct"] == 24.5

    Rebasings.reject!(r, "admin@test")
    refute National.rebasing(National.document(), "GHA")
  end

  test "the alert closes once a newer IMF edition has caught up" do
    edition = Rebasings.current_edition()
    imf = National.imf_value("TCD", "gdp_usd_bn", 2025)

    # Chad, no official figure: the IMF's GDP rose by more than half the revision.
    {:ok, tcd} =
      Rebasings.create(
        %{
          "country_code" => "TCD",
          "announced_on" => "2026-03-02",
          "old_base" => "2005",
          "new_base" => "2017",
          "level_change_pct" => "20",
          "reference_year" => 2025,
          "source_name" => "INSEED",
          "source_url" => "https://inseed.td/rebasage"
        },
        "admin@test"
      )

    # Same edition: nothing to compare yet.
    assert National.rebasing(National.document(), "TCD")["active"]

    # As if it had been published under the previous edition, at a lower GDP.
    older = fn r, before ->
      r
      |> Ecto.Changeset.change(imf_edition: "2000-04", imf_before: before)
      |> Repo.update!()
    end

    older.(tcd, :erlang.float_to_binary(imf / 1.2, decimals: 3))
    # Senegal: the IMF's 2021 GDP has not risen by half the 13.5 % revision.
    sen_imf = National.imf_value("SEN", "gdp_usd_bn", 2021)

    older.(
      Repo.get_by!(Rebasing, country_code: "SEN"),
      :erlang.float_to_binary(sen_imf, decimals: 3)
    )

    National.rebuild!()

    closed = National.rebasing(National.document(), "TCD")
    refute closed["active"]
    assert closed["integrated_edition"] == edition
    assert National.rebasing(National.document(), "SEN")["active"]
  end

  test "a person can close an alert the check missed" do
    eth = Repo.get_by!(Rebasing, country_code: "ETH")
    Rebasings.mark_integrated!(eth, "admin@test")
    refute National.rebasing(National.document(), "ETH")["active"]
  end
end
