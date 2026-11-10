defmodule SyliAtlas.Market.QuotaTest do
  use SyliAtlas.DataCase, async: false
  use Oban.Testing, repo: SyliAtlas.Repo, engine: Oban.Engines.Lite

  alias SyliAtlas.Market.{Ingestion, RawPayload}
  alias SyliAtlas.MarketFixtures, as: F
  alias SyliAtlas.Workers.MarketImportWorker

  setup do
    SyliAtlas.Geo.seed_areas!()
    SyliAtlas.Market.seed!()
    :ok
  end

  test "a daily limit answer stops the import at once, without retry, and plans the next try" do
    counter = :counters.new(1, [])

    Req.Test.stub(SyliAtlas.Market.Sources.Mansa, fn conn ->
      :counters.add(counter, 1, 1)

      if :counters.get(counter, 1) <= 3 do
        F.mansa_plug(conn)
      else
        conn
        |> Plug.Conn.put_status(429)
        |> Req.Test.json(%{
          "success" => false,
          "error" => %{
            "code" => "RATE_LIMIT_EXCEEDED",
            "reset_at" => "2099-01-02T00:00:00.000Z"
          }
        })
      end
    end)

    assert {:ok, _} = MarketImportWorker.run("mansa", SyliAtlas.Market.Sources.Mansa)

    # three answers kept, one refused call, no retry and no further call
    assert :counters.get(counter, 1) == 4
    assert Repo.aggregate(RawPayload, :count) == 3
    assert Ingestion.calls("mansa") >= 95

    assert_enqueued(
      worker: MarketImportWorker,
      args: %{"source" => "mansa"},
      scheduled_at: ~U[2099-01-02 00:10:00Z]
    )
  end

  test "without a key the job is cancelled and says why" do
    config = Application.get_env(:syli_atlas, SyliAtlas.Market.Sources.Mansa)

    Application.put_env(
      :syli_atlas,
      SyliAtlas.Market.Sources.Mansa,
      Keyword.put(config, :api_key, nil)
    )

    on_exit(fn -> Application.put_env(:syli_atlas, SyliAtlas.Market.Sources.Mansa, config) end)

    assert {:cancel, _} = perform_job(MarketImportWorker, %{})
  end
end
