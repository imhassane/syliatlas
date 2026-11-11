defmodule SyliAtlas.Market.MansaFakeTest do
  use SyliAtlasWeb.ConnCase, async: false

  alias SyliAtlas.Market.Sources.{Mansa, MansaFake}

  setup do
    previous = Application.get_env(:syli_atlas, Mansa)
    previous_market = Application.get_env(:syli_atlas, SyliAtlas.Market)
    Application.put_env(:syli_atlas, Mansa, req_options: [plug: MansaFake, retry: false])
    Application.put_env(:syli_atlas, SyliAtlas.Market, Keyword.put(previous_market, :fake, true))

    on_exit(fn ->
      Application.put_env(:syli_atlas, Mansa, previous)
      Application.put_env(:syli_atlas, SyliAtlas.Market, previous_market)
    end)
  end

  test "answers every endpoint the importer calls, in Mansa's shapes, without a key" do
    assert Mansa.configured?()

    for {dataset, ext} <- [
          {"exchanges", nil},
          {"indices", nil},
          {"forex", nil},
          {"etfs", nil},
          {"stocks", "south-africa"}
        ] do
      assert {:ok, [first | _] = pages} = Mansa.fetch(dataset, ext, [])
      assert first.status == 200
      assert {:ok, records} = Mansa.parse(dataset, first.body, %{})
      assert records != [], "#{dataset}: no records"
      if dataset == "stocks", do: assert(length(pages) == 1)
    end

    assert {:ok, [body]} = Mansa.fetch("indices", nil, [])
    assert {:ok, records} = Mansa.parse("indices", body.body, %{})
    assert Enum.all?(records, &is_float(&1.ytd_pct))
  end

  test "no quota is spent, even once today's real quota is used up" do
    SyliAtlas.Market.Ingestion.exhaust!("mansa")
    assert {:ok, [_]} = Mansa.fetch("exchanges", nil, [])
  end

  test "MANSA_FAKE is refused in the Railway environment named production" do
    System.put_env(%{"MANSA_FAKE" => "true", "RAILWAY_ENVIRONMENT_NAME" => "production"})
    on_exit(fn -> Enum.each(~w(MANSA_FAKE RAILWAY_ENVIRONMENT_NAME), &System.delete_env/1) end)

    assert_raise RuntimeError, ~r/refused in production/, fn ->
      Config.Reader.read!("config/runtime.exs", env: :dev)
    end

    System.put_env("RAILWAY_ENVIRONMENT_NAME", "development")
    config = Config.Reader.read!("config/runtime.exs", env: :dev)
    assert config[:syli_atlas][SyliAtlas.Market][:fake]
    assert config[:syli_atlas][Mansa][:req_options][:plug] == MansaFake
  end

  test "the same trading day gives the same figures; the next one moves" do
    friday = ~D[2026-11-13]
    assert MansaFake.trading_day(~D[2026-11-15]) == friday
    assert MansaFake.exchanges(friday) == MansaFake.exchanges(friday)

    a = MansaFake.stocks("ivory-coast", friday, %{})
    b = MansaFake.stocks("ivory-coast", ~D[2026-11-16], %{})
    assert hd(a["data"])["price"] != hd(b["data"])["price"]
    assert Enum.all?(a["data"], &(&1["price"] > 0))
    assert hd(a["data"])["name"] =~ "Démo"
  end

  test "a full import with the stand-in publishes pages that say the figures are fictitious" do
    SyliAtlas.Geo.seed_areas!()
    SyliAtlas.Market.seed!()
    :ok = SyliAtlas.Workers.MarketImportWorker.run("mansa", Mansa)
    Oban.drain_queue(queue: :market, with_scheduled: true)

    assert %{"securities" => [_ | _]} = SyliAtlas.Market.exchange("brvm")

    html = build_conn() |> get("/fr/bourses/brvm") |> html_response(200)
    assert html =~ "Chiffres fictifs (développement)"
    refute html =~ "Data by MansaAPI"
    refute html =~ "https://mansaapi.com"
  end
end
