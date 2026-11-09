defmodule SyliAtlas.Profiles.Queries do
  @moduledoc """
  The JSON functions: one SQLite query per screen, which returns the whole
  JSON answer. They read the precomputed JSONB documents only, so each one
  stays well under the 1.5 ms budget. The reference year is a parameter:
  values are read from the series arrays at `year - 2015`.

  Indicator names are checked against `SyliAtlas.Sources.Indicators`
  before they reach SQL; every other input is a bound parameter.
  """
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
          'changes', (
            SELECT json_group_object(s.key,
              CASE WHEN s.key IN ('real_gdp_growth', 'inflation', 'public_debt_pct_gdp')
                THEN round(json_extract(s.value, '$[' || (?3 - #{@first}) || ']')
                         - json_extract(s.value, '$[' || (?2 - #{@first}) || ']'), 1)
                ELSE round((json_extract(s.value, '$[' || (?3 - #{@first}) || ']')
                          / json_extract(s.value, '$[' || (?2 - #{@first}) || ']') - 1) * 100, 1)
              END)
            FROM json_each(p.doc, '$.series') AS s)))
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
          'name', json_extract(p.doc, '$.name'),
          'slug', json_extract(p.doc, '$.slug'),
          'kind', json_extract(p.doc, '$.kind'),
          'series', json(jsonb_extract(p.doc, '$.series')),
          'real_gdp_change_pct', #{change_sql("real_gdp_index")}
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
               CASE WHEN ?5 = 'en' THEN a.name_en ELSE a.name_fr END AS name,
               CASE WHEN ?5 = 'en' THEN a.slug_en ELSE a.slug_fr END AS slug,
               #{expr} AS v
        FROM profiles AS p
        JOIN areas AS a ON a.code = p.area_code
        WHERE a.kind = 'country' AND (?4 IS NULL OR a.region_code = ?4)
        ORDER BY v IS NULL, v DESC)
      """,
      [nil, from, to, Keyword.get(opts, :region), Keyword.get(opts, :locale, "fr")]
    )
  end

  @doc "Areas whose name matches, accents and case ignored."
  def search(query, locale \\ "fr") do
    q = "%" <> SyliAtlas.Geo.Area.normalize(String.slice(query || "", 0, 60)) <> "%"

    run(
      :search,
      """
      SELECT json_group_array(json_object('code', code, 'kind', kind, 'name', name, 'slug', slug)) FROM (
        SELECT code, kind,
               CASE WHEN ?2 = 'en' THEN name_en ELSE name_fr END AS name,
               CASE WHEN ?2 = 'en' THEN slug_en ELSE slug_fr END AS slug
        FROM areas WHERE search_text LIKE ?1
        ORDER BY kind <> 'country', name LIMIT 10)
      """,
      [q, locale]
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
end
