defmodule SyliAtlas.Budgets.ResearchTest do
  use SyliAtlas.DataCase, async: false

  alias SyliAtlas.{BudgetFixtures, Budgets, Repo}
  alias SyliAtlas.Budgets.Proposal

  setup do
    BudgetFixtures.seed!()
    :ok
  end

  test "the bundled research file becomes pending proposals, never laws" do
    rows = Budgets.research_path() |> File.read!() |> Jason.decode!() |> Map.fetch!("proposals")

    assert Budgets.seed_research!() == length(rows)

    proposals = Repo.all(Proposal)
    assert length(proposals) == length(rows)
    assert Enum.all?(proposals, &(&1.status == "pending" and &1.origin == "research"))
    assert Enum.all?(proposals, &String.starts_with?(&1.source_url, "https://"))
    assert Budgets.overview()["counts"]["official"] == 0

    # Warnings for missing figures are expected; no blocking error, and
    # the dollar budgets of Liberia and Somalia are accepted.
    refute Enum.any?(proposals, &SyliAtlas.Budgets.Checks.errors?(&1.checks))

    mali = Enum.find(proposals, &(&1.country_code == "MLI" and &1.kind == "initial"))
    assert Decimal.equal?(mali.expenditure, Decimal.new("3578217000000"))
    assert mali.evidence["note"] =~ "communiqué"
    assert mali.evidence["found_on"] == "2026-11-12"
  end

  test "running it again, or after a rejection, adds nothing" do
    first = Budgets.seed_research!()
    assert first > 0

    Repo.all(Proposal) |> Enum.take(3) |> Enum.each(&Budgets.reject/1)

    assert Budgets.seed_research!() == 0
    assert Repo.aggregate(Proposal, :count) == first
  end

  test "covers every country that votes or decrees a budget" do
    codes =
      Budgets.research_path()
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("proposals")
      |> MapSet.new(& &1["country_code"])

    # Eritrea publishes no budget.
    assert MapSet.size(codes) == 53
    refute MapSet.member?(codes, "ERI")
  end
end
