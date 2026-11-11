defmodule SyliAtlas.Profiles.Queries do
  @moduledoc """
  The JSON functions: one SQLite query per screen, which returns the whole
  JSON answer. They read the precomputed JSONB documents only, so each one
  stays well under the 1.5 ms budget. The reference year is a parameter:
  values are read from the series arrays at `year - 2015`.

  Indicator names are checked against `SyliAtlas.Sources.Indicators`
  before they reach SQL; every other input is a bound parameter.
  """
  @locales SyliAtlas.Locales.all()

  alias SyliAtlas.Repo
  alias SyliAtlas.Sources.Indicators

  @first Indicators.first_year()

  defguardp valid_year(y) when is_integer(y) and y >= 2015 and y <= 2030

  @doc "Profile of one area plus every indicator's change over the period."
  def area_profile(code, from, to) when valid_year(from) and valid_year(to) do
    run(
      :area_profile,
      """
      SELECT json_object(
        'profile', json(p.doc),
        'period', json_object(
          'from', ?2, 'to', ?3,
          'changes', json((
            SELECT json_group_object(s.key,
              CASE WHEN s.key IN (#{rate_list()})
                THEN round(json_extract(s.value, '$[' || (?3 - #{@first}) || ']')
                         - json_extract(s.value, '$[' || (?2 - #{@first}) || ']'), 1)
                ELSE round((json_extract(s.value, '$[' || (?3 - #{@first}) || ']')
                          / json_extract(s.value, '$[' || (?2 - #{@first}) || ']') - 1) * 100, 1)
              END)
            FROM json_each(p.doc, '$.series') AS s))))
      FROM profiles AS p
      WHERE p.area_code = ?1
      """,
      [code, from, to]
    )
  end

  @doc "Several areas side by side, in the given order."
  def compare(codes, from, to) when is_list(codes) and valid_year(from) and valid_year(to) do
    run(
      :compare,
      """
      SELECT json_group_array(json(item)) FROM (
        SELECT json_object(
          'code', p.area_code,
          'name', json(jsonb_extract(p.doc, '$.name')),
          'slug', json(jsonb_extract(p.doc, '$.slug')),
          'kind', jsonb_extract(p.doc, '$.kind'),
          'series', json(jsonb_extract(p.doc, '$.series')),
          'real_gdp_change_pct', #{change_sql("real_gdp_index")},
          'gdp_change_pct', #{change_sql("gdp_usd_bn")}
        ) AS item
        FROM json_each(?1) AS c
        JOIN profiles AS p ON p.area_code = c.value
        ORDER BY c.key)
      """,
      [Jason.encode!(Enum.take(codes, 6)), from, to]
    )
  end

  @doc """
  Countries ranked by an indicator: its value in `to` (mode "value") or its
  change between `from` and `to` (mode "change"). Optionally one region.
  """
  def ranking(indicator, from, to, opts \\ []) when valid_year(from) and valid_year(to) do
    true = Indicators.valid?(indicator)
    mode = Keyword.get(opts, :mode, "change")
    expr = if mode == "value", do: value_sql(indicator, "?3"), else: change_sql(indicator)

    run(
      :ranking,
      """
      SELECT json_group_array(json_object('code', code, 'name', name, 'slug', slug,
                                          'region', region, 'value', v)) FROM (
        SELECT a.code, a.region_code AS region,
               CASE WHEN ?5 = 'fr' THEN a.name_fr
                    ELSE coalesce(json_extract(p.doc, '$.name.' || ?5), a.name_en) END AS name,
               CASE WHEN ?5 = 'fr' THEN a.slug_fr
                    ELSE coalesce(json_extract(p.doc, '$.slug.' || ?5), a.slug_en) END AS slug,
               #{expr} AS v
        FROM profiles AS p
        JOIN areas AS a ON a.code = p.area_code
        WHERE a.kind = 'country' AND (?4 IS NULL OR a.region_code = ?4)
        ORDER BY v IS NULL, v DESC)
      """,
      [nil, from, to, Keyword.get(opts, :region), Keyword.get(opts, :locale, "fr")]
    )
  end

  @doc """
  Every country for the home map, read from its snapshot (built once per
  edition by `refresh_snapshots!/0`): figures in the default arrival year,
  GDP in current dollars and its change since the default reference year,
  rank in Africa by GDP, and the GDP series for the panel's sparkline.
  """
  def map_countries(locale \\ "fr") when locale in @locales do
    run(:map_countries, "SELECT json(doc) FROM snapshots WHERE key = ?1", ["map:" <> locale])
  end

  @doc "The home page (`SyliAtlas.Profiles.HomeSnapshot`), in one row."
  def home(locale) when locale in @locales do
    run(:home, "SELECT json(doc) FROM snapshots WHERE key = ?1", ["home:" <> locale])
  end

  @doc "The regions page for the default period (`SyliAtlas.Profiles.RegionsSnapshot`), in one row."
  def regions(locale) when locale in @locales do
    run(:regions, "SELECT json(doc) FROM snapshots WHERE key = ?1", ["regions:" <> locale])
  end

  @doc "True when a profile lacks the name of a language of the site."
  def missing_locales? do
    missing = Enum.map_join(@locales, " OR ", &"json_extract(doc, '$.name.#{&1}') IS NULL")

    case Repo.query!("SELECT count(*) FROM profiles WHERE " <> missing).rows do
      [[0]] -> false
      _ -> true
    end
  end

  @doc "Format number of a stored snapshot, nil when it is missing."
  def snapshot_format(key) do
    case Repo.query!("SELECT json_extract(doc, '$.format') FROM snapshots WHERE key = ?1", [key]).rows do
      [[format]] -> format
      [] -> nil
    end
  end

  @doc "Records the daily check in the home snapshots (the « last check » line)."
  def touch_checked_at!(%DateTime{} = at) do
    Repo.query!(
      "UPDATE snapshots SET doc = jsonb_set(doc, '$.last_checked_at', ?1), updated_at = ?2 WHERE key LIKE 'home:%'",
      [DateTime.to_iso8601(at), at |> DateTime.truncate(:second) |> DateTime.to_iso8601()]
    )

    :ok
  end

  @doc "Rebuilds the snapshots from the profiles. Run inside the rebuild transaction."
  def refresh_snapshots! do
    {from, to} = SyliAtlas.Profiles.Builder.default_period()
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    for locale <- @locales do
      Repo.query!(
        """
        INSERT INTO snapshots (key, doc, inserted_at, updated_at)
        VALUES ('map:' || ?1, jsonb((#{map_sql()})), ?4, ?4)
        ON CONFLICT(key) DO UPDATE SET doc = excluded.doc, updated_at = excluded.updated_at
        """,
        [locale, from, to, now]
      )
    end

    # The home page reads the map just written, so it comes after it.
    for locale <- @locales do
      put_snapshot!("home:" <> locale, SyliAtlas.Profiles.HomeSnapshot.build(locale), now)

      put_snapshot!(
        "regions:" <> locale,
        SyliAtlas.Profiles.RegionsSnapshot.build(locale, from, to),
        now
      )
    end

    :ok
  end

  defp put_snapshot!(key, doc, now) do
    Repo.query!(
      """
      INSERT INTO snapshots (key, doc, inserted_at, updated_at) VALUES (?1, jsonb(?2), ?3, ?3)
      ON CONFLICT(key) DO UPDATE SET doc = excluded.doc, updated_at = excluded.updated_at
      """,
      [key, Jason.encode!(doc), now]
    )
  end

  # ?1 locale, ?2 reference year, ?3 arrival year.
  defp map_sql do
    """
    SELECT json_object('from', ?2, 'to', ?3, 'countries', json_group_array(json_object(
      'code', code, 'name', name, 'slug', slug, 'region', region, 'region_name', region_name,
      'region_slug', region_slug,
      'gdp', gdp, 'gdp_change', gdp_change, 'real_change', real_change,
      'rank', CASE WHEN gdp IS NULL THEN NULL ELSE rnk END, 'of', ranked,
      'gdppc', gdppc, 'inflation', inflation, 'debt', debt, 'growth', growth,
      'series', json(gdp_series)))) FROM (
      SELECT *, rank() OVER (ORDER BY gdp IS NULL, gdp DESC) AS rnk,
             count(gdp) OVER () AS ranked
      FROM (
        SELECT a.code, a.region_code AS region,
               coalesce(json_extract(p.doc, '$.name.' || ?1), a.name_en) AS name,
               coalesce(json_extract(p.doc, '$.slug.' || ?1), a.slug_en) AS slug,
               coalesce(json_extract(rp.doc, '$.name.' || ?1), r.name_en) AS region_name,
               coalesce(json_extract(rp.doc, '$.slug.' || ?1), r.slug_en) AS region_slug,
               #{value_sql("gdp_usd_bn", "?3")} AS gdp,
               #{change_sql("gdp_usd_bn")} AS gdp_change,
               #{change_sql("real_gdp_index")} AS real_change,
               #{value_sql("gdp_per_capita_usd", "?3")} AS gdppc,
               #{value_sql("inflation", "?3")} AS inflation,
               #{value_sql("public_debt_pct_gdp", "?3")} AS debt,
               #{value_sql("real_gdp_growth", "?3")} AS growth,
               jsonb_extract(p.doc, '$.series.gdp_usd_bn') AS gdp_series
        FROM profiles AS p
        JOIN areas AS a ON a.code = p.area_code
        LEFT JOIN areas AS r ON r.code = a.region_code
        LEFT JOIN profiles AS rp ON rp.area_code = a.region_code
        WHERE a.kind = 'country')
      ORDER BY rnk)
    """
  end

  @doc "Areas whose name matches, accents and case ignored."
  def search(query, locale \\ "fr") do
    q = "%" <> SyliAtlas.Geo.Area.normalize(String.slice(query || "", 0, 60)) <> "%"

    run(
      :search,
      """
      SELECT json_group_array(json_object('code', code, 'kind', kind, 'name', name, 'slug', slug)) FROM (
        SELECT code, kind,
               CASE WHEN ?2 = 'fr' THEN name_fr
                    ELSE coalesce(json_extract(p.doc, '$.name.' || ?2), name_en) END AS name,
               CASE WHEN ?2 = 'fr' THEN slug_fr
                    ELSE coalesce(json_extract(p.doc, '$.slug.' || ?2), slug_en) END AS slug
        FROM areas LEFT JOIN profiles AS p ON p.area_code = areas.code
        WHERE search_text LIKE ?1
        ORDER BY kind <> 'country', name LIMIT 10)
      """,
      [q, locale]
    )
  end

  @doc "Name, slug and series of any number of areas, in the given order (community pages)."
  def series_for(codes) when is_list(codes) do
    run(
      :series_for,
      """
      SELECT json_group_array(json(item)) FROM (
        SELECT json_object(
          'code', p.area_code,
          'name', json(jsonb_extract(p.doc, '$.name')),
          'slug', json(jsonb_extract(p.doc, '$.slug')),
          'series', json(jsonb_extract(p.doc, '$.series'))
        ) AS item
        FROM json_each(?1) AS c
        JOIN profiles AS p ON p.area_code = c.value
        ORDER BY c.key)
      """,
      [Jason.encode!(codes)]
    )
  end

  @doc "Every document at once, for the offline pack of the installed app."
  def offline_pack do
    run(
      :offline_pack,
      """
      SELECT json_object(
        'version', (SELECT max(updated_at) || '-' || count(*) FROM profiles),
        'profiles', json_group_object(area_code, json(doc)))
      FROM profiles
      """,
      []
    )
  end

  defp value_sql(indicator, year_param),
    do: "json_extract(p.doc, '$.series.#{indicator}[' || (#{year_param} - #{@first}) || ']')"

  defp change_sql(indicator) do
    a = value_sql(indicator, "?2")
    b = value_sql(indicator, "?3")

    case Indicators.get(indicator).kind do
      :rate -> "round(#{b} - #{a}, 1)"
      _ -> "round((#{b} / #{a} - 1) * 100, 1)"
    end
  end

  # Runs one function, times it for the admin, returns the raw JSON text.
  defp run(name, sql, params) do
    start = System.monotonic_time()
    %{rows: rows} = Repo.query!(sql, params, log: false)
    duration = System.monotonic_time() - start

    json =
      case rows do
        [[json]] when is_binary(json) -> json
        _ -> nil
      end

    :telemetry.execute([:syli_atlas, :json_fn, :stop], %{duration: duration}, %{
      name: name,
      rows: length(rows)
    })

    json
  end

  # Rates change in percentage points; the list comes from the indicator
  # definitions, never from user input.
  defp rate_list, do: Enum.map_join(Indicators.rate_keys(), ", ", &"'#{&1}'")
end
