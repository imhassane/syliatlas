defmodule SyliAtlas.Market.PipelineTest do
  use SyliAtlas.DataCase, async: false

  alias SyliAtlas.Market

  alias SyliAtlas.Market.{
    Consolidation,
    EodPrice,
    IndexValue,
    Ingestion,
    Observation,
    Pipeline,
    QualityIssue,
    RawPayload,
    Reference,
    Security,
    SourcePriority
  }

  alias SyliAtlas.MarketFixtures, as: F

  setup do
    F.import!()
    :ok
  end

  test "a full import keeps every payload raw, with its receipt" do
    payloads = Repo.all(RawPayload)
    # exchanges, indices, 21 exchanges' stocks (Johannesburg on two pages), funds, rates
    assert length(payloads) == 26
    assert Enum.all?(payloads, &(&1.parsed_at != nil and &1.parser_version == 1))
    assert Enum.all?(payloads, &(String.length(&1.sha256) == 64))
    p = Enum.find(payloads, &(&1.dataset == "forex"))
    assert {:ok, body} = Ingestion.body(p)
    assert body =~ "USD/XOF"
    assert Ingestion.calls("mansa") == 26
  end

  test "securities are created from the rank 1 source, with their country when the exchange has one" do
    brvm = Reference.get_exchange("brvm")
    jse = Reference.get_exchange("jse")
    assert Repo.aggregate(from(s in Security, where: s.exchange_id == ^brvm.id), :count) == 5
    assert Repo.aggregate(from(s in Security, where: s.exchange_id == ^jse.id), :count) == 250
    assert Repo.get_by!(Security, ticker: "ZA1").country_code == "ZAF"
    # A regional exchange: the country is left to the reference.
    assert Repo.get_by!(Security, ticker: "ALPT").country_code == nil
    assert Repo.get_by!(Security, ticker: "GOLDX").kind == "etf"
  end

  test "closes are published exactly, each with the observation it comes from" do
    alpt = Repo.get_by!(Security, ticker: "ALPT")
    [price] = Repo.all(from p in EodPrice, where: p.security_id == ^alpt.id)
    assert Decimal.equal?(price.close, Decimal.new("4000"))
    assert Decimal.equal?(price.change_pct, Decimal.new("-1.2346"))
    assert price.source == "mansa"
    obs = Repo.get!(Observation, price.observation_id)
    assert obs.subject_id == alpt.id and obs.raw_payload_id != nil
  end

  test "a held share is stored but not published" do
    ecla = Repo.get_by!(Security, ticker: "ECLA")

    assert Repo.exists?(
             from o in Observation,
               where: o.subject_type == "security" and o.subject_id == ^ecla.id
           )

    refute Repo.exists?(from p in EodPrice, where: p.security_id == ^ecla.id)

    assert Repo.get_by!(QualityIssue, subject_id: ecla.id, rule: "abnormal_change").status ==
             "open"
  end

  test "indices: published with their change since 1 January, missing and old ones reported" do
    brvm = Reference.get_exchange("brvm")
    [v] = Repo.all(from v in IndexValue, where: v.exchange_id == ^brvm.id)
    assert Decimal.equal?(v.value, Decimal.new("520.74"))
    assert Decimal.equal?(v.ytd_pct, Decimal.new("50.61"))

    egx = Reference.get_exchange("egx")
    refute Repo.exists?(from v in IndexValue, where: v.exchange_id == ^egx.id)

    assert Repo.get_by!(QualityIssue, subject_id: egx.id, subject_type: "index").rule ==
             "index_missing"

    mse = Reference.get_exchange("mse")
    assert Repo.get_by!(QualityIssue, subject_id: mse.id, subject_type: "index", rule: "stale")

    jse = Reference.get_exchange("jse")

    assert Repo.get_by!(QualityIssue,
             subject_id: jse.id,
             subject_type: "index",
             rule: "suspect_change"
           )
  end

  test "processing a payload again changes nothing" do
    before = {Repo.aggregate(Observation, :count), Repo.aggregate(EodPrice, :count)}
    for id <- Repo.all(from p in RawPayload, select: p.id), do: {:ok, _} = Pipeline.process(id)
    assert {Repo.aggregate(Observation, :count), Repo.aggregate(EodPrice, :count)} == before

    assert Repo.aggregate(from(q in QualityIssue, where: q.status == "open"), :count) ==
             Repo.aggregate(QualityIssue, :count)
  end

  test "the published value follows the source ranking of the exchange" do
    alpt = Repo.get_by!(Security, ticker: "ALPT")
    brvm = Reference.get_exchange("brvm")
    date = F.day()
    payload = Repo.get_by!(RawPayload, dataset: "stocks", exchange_code: "brvm")

    Repo.insert!(%Observation{
      subject_type: "security",
      subject_id: alpt.id,
      trade_date: date,
      source: "brvm_boc",
      close: Decimal.new("4010"),
      currency: "XOF",
      raw_payload_id: payload.id,
      parser_version: 1,
      ingested_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })

    # Shadow mode: the official list is read but Mansa stays published.
    Consolidation.consolidate_security!(alpt.id, date)
    assert Repo.get_by!(EodPrice, security_id: alpt.id).source == "mansa"

    # Switch: the official list becomes rank 1, Mansa the backup.
    Repo.update_all(
      from(p in SourcePriority, where: p.exchange_id == ^brvm.id and p.dataset == "prices"),
      set: [rank: 2]
    )

    Repo.insert!(%SourcePriority{
      exchange_id: brvm.id,
      dataset: "prices",
      source: "brvm_boc",
      rank: 1,
      valid_from: ~D[2026-01-01]
    })

    Consolidation.consolidate_security!(alpt.id, date)
    price = Repo.get_by!(EodPrice, security_id: alpt.id)
    assert price.source == "brvm_boc" and Decimal.equal?(price.close, Decimal.new("4010"))
  end

  test "documents for the pages: overview, exchange, funds, rates" do
    overview = Market.overview()
    assert overview["totals"]["exchanges"] == 21
    assert overview["totals"]["securities"] == 257
    assert overview["totals"]["missing"] == 2
    assert overview["totals"]["stale"] == 1
    brvm = Enum.find(overview["exchanges"], &(&1["exchange"]["code"] == "brvm"))
    assert brvm["index"]["value"] == "520.74"
    assert brvm["exchange"]["search"] =~ "cote d'ivoire"

    doc = Market.exchange("brvm")
    assert doc["session"]["up"] == 1 and doc["session"]["down"] == 2
    assert hd(doc["securities"])["ticker"] == "ALPT"
    assert doc["session"]["top"]["ticker"] == "ALPT"
    assert Enum.map(doc["movers_up"], & &1["ticker"]) == ["CACI"]
    assert Enum.find(doc["securities"], &(&1["ticker"] == "ECLA"))["flags"]["held"]
    assert Enum.find(doc["securities"], &(&1["ticker"] == "DUNE"))["flags"]["no_trade"]

    assert length(Market.etfs()["etfs"]) == 2
    assert Market.fx()["rates"]["USD/XOF"] == 600.0
    assert_in_delta Market.to_usd(6000.0, "XOF", Market.fx()), 10.0, 0.001
  end

  test "a country's block lists its exchange and its own companies" do
    [ngx] = Market.for_country("NGA")
    assert ngx["exchange"]["code"] == "ngx" and ngx["regional"] == false
    [brvm] = Market.for_country("CIV")
    assert brvm["regional"]
    assert Market.for_country("FRA") == []
  end

  test "the quota is checked before each call" do
    Repo.query!("UPDATE market_api_usage SET calls = 95")
    assert {:error, :quota_exhausted} = Ingestion.reserve("mansa")
    assert {:error, :quota_exhausted} = SyliAtlas.Market.Sources.Mansa.fetch("forex", nil, [])
    assert Ingestion.calls("mansa") == 95
  end
end
