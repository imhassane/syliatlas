defmodule SyliAtlas.BudgetFixtures do
  @moduledoc "Budget catalog, proposals and laws for tests (figures of Mali's 2026 laws)."
  alias SyliAtlas.Budgets

  def seed! do
    SyliAtlas.Geo.seed_areas!()
    Budgets.seed!()
  end

  def law_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "country_code" => "MLI",
        "fiscal_year" => 2026,
        "kind" => "amending",
        "stage" => "voted",
        "reference" => "LFR 2026",
        "legislature" => "Conseil national de Transition",
        "voted_on" => "2026-07-09",
        "votes_for" => 121,
        "revenue" => "3372895000000",
        "expenditure" => "3993319000000",
        "currency" => "XOF",
        "source_name" => "Journal officiel de la République du Mali",
        "source_url" => "https://sgg-mali.ml/JO/2026/mali-jo-2026-15.pdf"
      },
      overrides
    )
  end

  @doc "A law published through the queue, as an administrator would."
  def publish!(overrides \\ %{}) do
    {:ok, p} = Budgets.propose(law_attrs(overrides))
    {:ok, law} = Budgets.approve(p, %{})
    Budgets.rebuild!()
    law
  end
end
