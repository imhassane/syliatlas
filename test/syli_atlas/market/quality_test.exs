defmodule SyliAtlas.Market.QualityTest do
  use SyliAtlas.DataCase, async: false
  alias SyliAtlas.Market.{Quality, QualityIssue}

  @today ~D[2026-11-10]
  @at ~U[2026-11-09 16:30:00Z]

  test "counts business days only" do
    assert Quality.business_days_between(~D[2026-11-06], ~D[2026-11-09]) == 1
    assert Quality.business_days_between(~D[2026-11-09], ~D[2026-11-09]) == 0
    assert Quality.business_days_between(~D[2026-10-27], ~D[2026-11-10]) == 10
  end

  test "an index without value is rejected and reported" do
    {verdict, issues, _} =
      Quality.check_index(%{value: nil, change_pct: nil, ytd_pct: nil, as_of: @at}, @today)

    assert verdict == :reject
    assert Enum.map(issues, & &1.rule) == ["index_missing"]
  end

  test "a daily change equal to the change since 1 January is flagged, not hidden" do
    {verdict, issues, _} =
      Quality.check_index(
        %{value: 112_739.38, change_pct: 2.67, ytd_pct: -2.67, as_of: @at},
        @today
      )

    assert verdict == :flag
    assert [%{rule: "suspect_change", severity: "high"}] = issues
  end

  test "an index silent for more than two business days is stale" do
    {:ok, old, 0} = DateTime.from_iso8601("2026-10-27T08:00:00Z")

    {_, issues, _} =
      Quality.check_index(%{value: 1.0, change_pct: 0.1, ytd_pct: nil, as_of: old}, @today)

    assert [%{rule: "stale", data: %{"as_of" => "2026-10-27"}}] = issues
  end

  test "a share moving 30 % on volume is held; one without trade is noted" do
    held = %{close: 2200, change_pct: 69.2, volume: 120, as_of: @at}
    assert {:hold, [%{rule: "abnormal_change"}], _} = Quality.check_security(held, @today)

    quiet = %{close: 1495, change_pct: nil, volume: nil, as_of: @at}

    assert {:ok, [%{rule: "no_trade", severity: "low"}], _} =
             Quality.check_security(quiet, @today)

    assert {:reject, [%{rule: "invalid_price"}], _} =
             Quality.check_security(%{close: 0, change_pct: nil, volume: 3, as_of: @at}, @today)
  end

  test "issues open once, then resolve themselves when the problem is gone" do
    issue = %{rule: "stale", severity: "mid", detail: "x", data: %{}}
    Quality.sync!("index", 1, ~D[2026-11-09], [issue], ["stale", "index_missing"])
    Quality.sync!("index", 1, ~D[2026-11-09], [issue], ["stale", "index_missing"])
    assert [%QualityIssue{status: "open"}] = Repo.all(QualityIssue)

    Quality.sync!("index", 1, ~D[2026-11-10], [], ["stale", "index_missing"])
    assert [%QualityIssue{status: "resolved", resolved_at: %DateTime{}}] = Repo.all(QualityIssue)
  end
end
