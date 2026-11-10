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

  test "the evening catch-up only fetches the exchanges still behind" do
    F.import!()
    alias SyliAtlas.Market.{EodPrice, Reference, Security}
    import Ecto.Query

    # every exchange is now up to date but the BRVM
    brvm = Reference.get_exchange("brvm")
    others = from(s in Security, where: s.exchange_id != ^brvm.id, select: s.id)

    Repo.update_all(from(p in EodPrice, where: p.security_id in subquery(others)),
      set: [trade_date: Date.utc_today()]
    )

    mine = from(s in Security, where: s.exchange_id == ^brvm.id, select: s.id)
    yesterday = Date.add(Date.utc_today(), -1)

    Repo.update_all(from(p in EodPrice, where: p.security_id in subquery(mine)),
      set: [trade_date: yesterday]
    )

    paths = :ets.new(:paths, [:bag, :public])

    Req.Test.stub(SyliAtlas.Market.Sources.Mansa, fn conn ->
      :ets.insert(paths, {conn.request_path})
      F.mansa_plug(conn)
    end)

    before = Repo.aggregate(RawPayload, :count)
    assert :ok = MarketImportWorker.run("mansa", SyliAtlas.Market.Sources.Mansa, "catchup")

    assert :ets.tab2list(paths) == [{"/api/v1/markets/exchanges/ivory-coast/stocks"}]
    assert Repo.aggregate(RawPayload, :count) == before + 1
  end

  test "the catch-up calls nothing when every exchange is up to date" do
    F.import!()
    Repo.update_all(SyliAtlas.Market.EodPrice, set: [trade_date: Date.utc_today()])
    Req.Test.stub(SyliAtlas.Market.Sources.Mansa, fn _ -> flunk("no call expected") end)
    assert :ok = MarketImportWorker.run("mansa", SyliAtlas.Market.Sources.Mansa, "catchup")
  end

  test "the two weekday passes are scheduled after Mansa's refreshes" do
    crontab =
      Application.get_env(:syli_atlas, Oban)[:plugins]
      |> Enum.find_value(fn
        {Oban.Plugins.Cron, opts} -> opts[:crontab]
        _ -> nil
      end)

    assert {"45 16 * * 1-5", MarketImportWorker} in crontab
    assert {"15 20 * * 1-5", MarketImportWorker, args: %{"mode" => "catchup"}} in crontab
  end
end
