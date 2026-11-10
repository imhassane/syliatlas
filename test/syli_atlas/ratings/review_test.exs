defmodule SyliAtlas.Ratings.ReviewTest do
  use SyliAtlas.DataCase, async: false

  alias SyliAtlas.Ratings
  alias SyliAtlas.Ratings.{Rating, Review}

  setup do
    SyliAtlas.Geo.seed_areas!()
    Ratings.seed!()
    :ok
  end

  defp proposal(attrs \\ %{}) do
    {:ok, p} =
      Review.propose(
        Map.merge(
          %{
            "country_code" => "civ",
            "agency" => "sp",
            "rating" => "BBB-",
            "outlook" => "stable",
            "action_date" => "2026-11-06",
            "action_type" => "upgrade"
          },
          attrs
        )
      )

    p
  end

  test "warnings flag a rating on another agency's scale and big jumps" do
    assert "wrong_scale" in proposal(%{"rating" => "Baa3"}).warnings
    assert "big_jump" in proposal(%{"rating" => "AA"}).warnings
    assert "type_mismatch" in proposal(%{"rating" => "B-", "action_type" => "upgrade"}).warnings
    assert proposal(%{"action_date" => ""}).warnings |> Enum.member?("no_date")
  end

  test "a duplicate of a pending proposal is refused" do
    proposal()

    assert {:error, _} =
             Review.propose(%{
               "country_code" => "CIV",
               "agency" => "sp",
               "rating" => "BBB-",
               "action_date" => "2026-11-06"
             })
  end

  test "approval needs the agency's own release, then publishes" do
    p = proposal()
    assert {:error, :missing_source} = Review.approve(p, %{})

    assert {:error, :not_agency_source} =
             Review.approve(p, %{"source_url" => "https://www.reuters.com/article"})

    assert {:ok, %Rating{}} =
             Review.approve(p, %{
               "source_url" => "https://www.spglobal.com/ratings/en/research/civ"
             })

    sp =
      Enum.find(
        Ratings.for_country(Ratings.document(), "CIV")["agencies"],
        &(&1["agency"] == "sp")
      )

    assert sp["rating"] == "BBB-"
    assert sp["source_url"] =~ "spglobal.com"
    assert Review.get!(p.id).status == "approved"
    assert {:error, :already_reviewed} = Review.approve(Review.get!(p.id), %{})
  end

  test "a checked row is no longer overwritten by the bundled file" do
    [row | _] = Review.to_check()

    assert {:ok, checked} =
             Review.mark_checked(row, %{"source_url" => source_for(row.agency)})

    refute checked.needs_check
    Ratings.seed!()
    refute SyliAtlas.Repo.get!(Rating, row.id).needs_check
    refute Enum.any?(Review.to_check(), &(&1.id == row.id))
  end

  test "the seed removes bundled rows the file no longer lists, but keeps approved ones" do
    stale =
      Ratings.put_rating!(%{
        country_code: "AGO",
        agency: "fitch",
        rating: "B-",
        action_date: "2001-01"
      })

    {:ok, p} =
      Review.propose(%{
        "country_code" => "KEN",
        "agency" => "fitch",
        "rating" => "B",
        "action_date" => "2026-11-01"
      })

    {:ok, approved} = Review.approve(p, %{"source_url" => "https://www.fitchratings.com/x"})

    Ratings.seed!()
    refute SyliAtlas.Repo.get(Rating, stale.id)
    assert SyliAtlas.Repo.get(Rating, approved.id)
  end

  test "rejecting keeps the rating online unchanged" do
    before = Ratings.document()["countries"]["CIV"]
    assert {:ok, %{status: "rejected"}} = Review.reject(proposal())
    assert Ratings.document()["countries"]["CIV"] == before
  end

  defp source_for("sp"), do: "https://disclosure.spglobal.com/x"
  defp source_for("moodys"), do: "https://ratings.moodys.com/x"
  defp source_for("fitch"), do: "https://www.fitchratings.com/x"
end
