defmodule SyliAtlas.Imports.BackfillTest do
  use SyliAtlas.DataCase, async: false
  alias SyliAtlas.Imports

  test "an edition imported before new indicators existed is filled on start" do
    SyliAtlas.Geo.seed_areas!()
    SyliAtlas.Sources.seed_sources!()

    payload =
      Application.app_dir(:syli_atlas, "priv/data/imf_weo_2026_10.json")
      |> File.read!()
      |> Jason.decode!()

    old = update_in(payload["values"], &Map.drop(&1, ~w(GGXCNL_NGDP BCA_NGDPD LUR)))
    {:ok, :published, _} = Imports.import_payload(payload["edition_label"], old)

    assert Enum.sort(Imports.missing_indicators()) ==
             ~w(current_account_pct_gdp fiscal_balance_pct_gdp unemployment)

    assert {:ok, :published, _} = Imports.backfill_missing_indicators!()
    assert Imports.missing_indicators() == []
    assert Imports.backfill_missing_indicators!() == :ok
  end
end
