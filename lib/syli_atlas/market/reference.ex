defmodule SyliAtlas.Market.Reference do
  @moduledoc """
  Our reference of African stock exchanges: codes, ISO 10383 MIC when
  known, currency, the countries each one serves, and how each source
  names them. Seeded at every start (idempotent upserts), like the areas.

  Securities are added by consolidation the first time the exchange's
  rank 1 source lists them; a ticker seen only by another source is never
  created automatically (it is reported instead), so a second source can
  not fill the reference with duplicates.
  """
  import Ecto.Query
  alias SyliAtlas.Repo
  alias SyliAtlas.Market.{Exchange, SourcePriority, SymbolMapping}

  @epoch ~D[2026-01-01]

  # code, mic, short name, name, currency, AU region, countries, timezone, index, Mansa id
  @exchanges [
    {"jse", "XJSE", "JSE", "Johannesburg Stock Exchange", "ZAR", "southern_africa", ~w(ZAF),
     "Africa/Johannesburg", "FTSE/JSE All Share (J203)", "south-africa"},
    {"egx", "XCAI", "EGX", "Egyptian Exchange", "EGP", "north_africa", ~w(EGY), "Africa/Cairo",
     "EGX 30", "egypt"},
    {"ngx", "XNSA", "NGX", "Nigerian Exchange", "NGN", "west_africa", ~w(NGA), "Africa/Lagos",
     "NGX All-Share Index", "nigeria"},
    {"casablanca", "XCAS", "Casablanca", "Bourse de Casablanca", "MAD", "north_africa", ~w(MAR),
     "Africa/Casablanca", "MASI", "morocco"},
    {"sem", "XMAU", "SEM", "Stock Exchange of Mauritius", "MUR", "east_africa", ~w(MUS),
     "Indian/Mauritius", "SEM All Share", "mauritius"},
    {"nse", "XNAI", "NSE", "Nairobi Securities Exchange", "KES", "east_africa", ~w(KEN),
     "Africa/Nairobi", "NASI", "kenya"},
    {"brvm", "XBRV", "BRVM", "Bourse Régionale des Valeurs Mobilières", "XOF", "west_africa",
     ~w(BEN BFA CIV GNB MLI NER SEN TGO), "Africa/Abidjan", "BRVM Composite", "ivory-coast"},
    {"bse", "XBOT", "BSE", "Botswana Stock Exchange", "BWP", "southern_africa", ~w(BWA),
     "Africa/Gaborone", "Domestic Companies Index", "botswana"},
    {"nsx", "XNAM", "NSX", "Namibian Stock Exchange", "NAD", "southern_africa", ~w(NAM),
     "Africa/Windhoek", "NSX Overall", "namibia"},
    {"gse", "XGHA", "GSE", "Ghana Stock Exchange", "GHS", "west_africa", ~w(GHA), "Africa/Accra",
     "GSE Composite Index", "ghana"},
    {"zse", "XZIM", "ZSE", "Zimbabwe Stock Exchange", "ZWG", "southern_africa", ~w(ZWE),
     "Africa/Harare", "ZSE All Share", "zimbabwe"},
    {"dse", "XDAR", "DSE", "Dar es Salaam Stock Exchange", "TZS", "east_africa", ~w(TZA),
     "Africa/Dar_es_Salaam", "DSE All Share Index", "tanzania"},
    {"luse", "XLUS", "LuSE", "Lusaka Securities Exchange", "ZMW", "southern_africa", ~w(ZMB),
     "Africa/Lusaka", "LuSE All Share (LASI)", "zambia"},
    {"use", "XUGA", "USE", "Uganda Securities Exchange", "UGX", "east_africa", ~w(UGA),
     "Africa/Kampala", "USE All Share", "uganda"},
    {"vfex", nil, "VFEX", "Victoria Falls Stock Exchange", "USD", "southern_africa", ~w(ZWE),
     "Africa/Harare", nil, "vfex"},
    {"mse", "XMSW", "MSE", "Malawi Stock Exchange", "MWK", "southern_africa", ~w(MWI),
     "Africa/Blantyre", "MASI", "malawi"},
    {"rse", nil, "RSE", "Rwanda Stock Exchange", "RWF", "east_africa", ~w(RWA), "Africa/Kigali",
     "RSE All Share", "rwanda"},
    {"ese", nil, "ESE", "Eswatini Stock Exchange", "SZL", "southern_africa", ~w(SWZ),
     "Africa/Mbabane", "ESE All Share", "eswatini"},
    {"bvmac", nil, "BVMAC", "Bourse des Valeurs Mobilières de l'Afrique Centrale", "XAF",
     "central_africa", ~w(CMR CAF TCD COG GNQ GAB), "Africa/Douala", nil, "bvmac"},
    {"sgbv", "XALG", "SGBV", "Bourse d'Alger", "DZD", "north_africa", ~w(DZA), "Africa/Algiers",
     "Dzair Index", "algeria"},
    {"bvc", nil, "BVC", "Bolsa de Valores de Cabo Verde", "CVE", "west_africa", ~w(CPV),
     "Atlantic/Cape_Verde", nil, "cape-verde"}
  ]

  def exchange_codes, do: Enum.map(@exchanges, &elem(&1, 0))

  @doc "Inserts or updates the exchanges, their Mansa identifiers and default source priorities."
  def seed! do
    @exchanges
    |> Enum.with_index()
    |> Enum.each(fn {{code, mic, short, name, cur, region, countries, tz, index, mansa}, i} ->
      exchange =
        (Repo.get_by(Exchange, code: code) || %Exchange{})
        |> Exchange.changeset(%{
          code: code,
          mic: mic,
          short_name: short,
          name: name,
          currency: cur,
          region_code: region,
          country_codes: countries,
          timezone: tz,
          index_name: index,
          position: i
        })
        |> Repo.insert_or_update!()

      ensure_mapping!("mansa", "exchange", mansa, exchange.id)

      for dataset <- ~w(prices indices) do
        ensure_priority!(exchange.id, dataset, "mansa", 1)
      end
    end)

    :ok
  end

  def list_exchanges, do: Repo.all(from e in Exchange, order_by: e.position)
  def get_exchange(code), do: Repo.get_by(Exchange, code: code)

  @doc "Our id for a source's identifier, as of a date."
  def resolve(source, subject_type, external_id, date \\ Date.utc_today()) do
    from(m in SymbolMapping,
      where:
        m.source == ^source and m.subject_type == ^subject_type and
          m.external_id == ^external_id and m.valid_from <= ^date and
          (is_nil(m.valid_to) or m.valid_to > ^date),
      select: m.subject_id,
      limit: 1
    )
    |> Repo.one()
  end

  @doc "All current mappings of a source for a subject type, as %{external_id => subject_id}."
  def mappings(source, subject_type) do
    today = Date.utc_today()

    from(m in SymbolMapping,
      where:
        m.source == ^source and m.subject_type == ^subject_type and m.valid_from <= ^today and
          (is_nil(m.valid_to) or m.valid_to > ^today),
      select: {m.external_id, m.subject_id}
    )
    |> Repo.all()
    |> Map.new()
  end

  def ensure_mapping!(source, subject_type, external_id, subject_id) do
    case resolve(source, subject_type, external_id) do
      ^subject_id ->
        :ok

      _ ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        Repo.insert!(
          %SymbolMapping{
            source: source,
            subject_type: subject_type,
            external_id: external_id,
            subject_id: subject_id,
            valid_from: @epoch,
            inserted_at: now,
            updated_at: now
          },
          on_conflict: [set: [subject_id: subject_id, valid_to: nil, updated_at: now]],
          conflict_target: [:source, :subject_type, :external_id, :valid_from]
        )

        :ok
    end
  end

  defp ensure_priority!(exchange_id, dataset, source, rank) do
    exists? =
      Repo.exists?(
        from p in SourcePriority,
          where: p.exchange_id == ^exchange_id and p.dataset == ^dataset and p.source == ^source
      )

    unless exists? do
      Repo.insert!(%SourcePriority{
        exchange_id: exchange_id,
        dataset: dataset,
        source: source,
        rank: rank,
        valid_from: @epoch
      })
    end
  end

  @doc "Sources by rank for an exchange and dataset, best first."
  def ranked_sources(exchange_id, dataset, date \\ Date.utc_today()) do
    case ranked(exchange_id, dataset, date) do
      # Before the first priorities (past closes from an index history),
      # the first priorities known apply.
      [] -> ranked(exchange_id, dataset, nil)
      sources -> sources
    end
  end

  defp ranked(exchange_id, dataset, date) do
    query =
      from(p in SourcePriority,
        where: p.exchange_id == ^exchange_id and p.dataset == ^dataset,
        order_by: [asc: p.rank, desc: p.valid_from],
        select: p.source
      )

    query =
      if date,
        do: where(query, [p], p.valid_from <= ^date),
        else: where(query, [p], p.valid_from == subquery(first_valid_from(exchange_id, dataset)))

    query |> Repo.all() |> Enum.uniq()
  end

  defp first_valid_from(exchange_id, dataset) do
    from p in SourcePriority,
      where: p.exchange_id == ^exchange_id and p.dataset == ^dataset,
      select: min(p.valid_from)
  end
end
