defmodule SyliAtlas.National.Snapshot do
  @moduledoc """
  The `national` document: each country's published figures (with the
  IMF's of the same year and the gap), its rebasing notice, and for every
  year the sum of national figures for Africa, with the IMF as fallback.
  """
  import Ecto.Query

  alias SyliAtlas.Repo
  alias SyliAtlas.National.{Figure, Rebasing}

  @format 2
  @first 2015
  @last 2030

  def format, do: @format

  def build do
    figures =
      Repo.all(
        from f in Figure,
          where: f.status in ^Figure.public_statuses(),
          order_by: [asc: f.country_code, asc: f.calendar_year]
      )

    imf = imf_series()

    rebasings =
      Repo.all(
        from r in Rebasing,
          where: r.status == "published",
          order_by: [desc: r.announced_on, asc: r.country_code]
      )

    notices = Enum.map(rebasings, &notice/1)

    countries =
      figures
      |> Enum.group_by(& &1.country_code)
      |> Map.new(fn {code, list} ->
        series = imf[code] || %{}
        by_indicator = list |> Enum.group_by(& &1.indicator)

        figs =
          Map.new(by_indicator, fn {ind, fs} ->
            {ind, Map.new(fs, &{Integer.to_string(&1.calendar_year), figure_doc(&1, series)})}
          end)

        {code, %{"figures" => figs, "rebasing" => latest_notice(notices, code)}}
      end)

    %{
      "format" => @format,
      "built_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "countries" => countries,
      "rebasings" => notices |> Enum.reverse() |> Map.new(&{&1["country_code"], &1}),
      "rebasing_list" => notices,
      "pending" => Enum.count(figures, &(&1.status == "pending_review")),
      "africa" =>
        Map.new(@first..@last, fn year ->
          {Integer.to_string(year), composite(year, imf, figures)}
        end)
    }
  end

  defp figure_doc(%Figure{} = f, series) do
    value = to_float(f.value)
    imf = at(series[f.indicator], f.calendar_year)
    pop = at(series["population_m"], f.calendar_year)

    %{
      "id" => f.id,
      "year" => f.calendar_year,
      "period" => f.period_label,
      "value" => value,
      "value_lcu" => to_float(f.value_lcu),
      "currency" => f.currency,
      "fx_rate" => to_float(f.fx_rate),
      "base_year" => f.base_year,
      "status" => f.status,
      "counted" => f.status in Figure.counted_statuses(),
      "source_name" => f.source_name,
      "source_url" => f.source_url,
      "published_on" => f.published_on,
      "quote" => f.quote,
      "extracted_by" => f.extracted_by,
      "imf" => imf,
      "gap_pct" => gap_pct(value, imf),
      # Syli Atlas calculation: the country's GDP over the IMF's population.
      "per_capita" =>
        if(f.indicator == "gdp_usd_bn" and is_number(pop) and pop > 0 and is_number(value),
          do: Float.round(value * 1000 / pop, 0)
        )
    }
  end

  defp latest_notice(notices, code), do: Enum.find(notices, &(&1["country_code"] == code))

  # What the pages show of a published rebasing. Active until an IMF
  # edition takes it in (see `SyliAtlas.National.Rebasings`).
  defp notice(%Rebasing{} = r) do
    %{
      "id" => r.id,
      "country_code" => r.country_code,
      "announced_on" => r.announced_on,
      "old_base" => r.old_base,
      "new_base" => r.new_base,
      "level_change_pct" => to_float(r.level_change_pct),
      "reference_year" => r.reference_year,
      "imf_before" => to_float(r.imf_before),
      "imf_edition" => r.imf_edition,
      "source_name" => r.source_name,
      "source_url" => r.source_url,
      "integrated_edition" => r.integrated_edition,
      "integrated_on" => r.integrated_on,
      "active" => is_nil(r.integrated_edition)
    }
  end

  @doc """
  The sum of national figures for Africa in a year: for each country, its
  counted GDP figure of the year, else the IMF's (fallback). Figures being
  checked are listed apart, with the sum they would give.
  """
  def composite(year, imf, figures) do
    gdp = Enum.filter(figures, &(&1.indicator == "gdp_usd_bn" and &1.calendar_year == year))

    counted =
      Map.new(Enum.filter(gdp, &(&1.status in Figure.counted_statuses())), &{&1.country_code, &1})

    pending = Map.new(Enum.filter(gdp, &(&1.status == "pending_review")), &{&1.country_code, &1})

    rows =
      imf
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {code, series} ->
        imf_v = at(series["gdp_usd_bn"], year)
        nat = counted[code]
        wait = pending[code]

        {retained, source} =
          cond do
            nat -> {to_float(nat.value), "national"}
            is_number(imf_v) -> {imf_v, "imf"}
            true -> {nil, "none"}
          end

        %{
          "code" => code,
          "imf" => imf_v,
          "national" => nat && to_float(nat.value),
          "pending" => wait && to_float(wait.value),
          "period" => (nat || wait) && (nat || wait).period_label,
          "retained" => retained,
          "source" => source
        }
      end)

    sum = fn key -> rows |> Enum.map(& &1[key]) |> Enum.filter(&is_number/1) |> Enum.sum() end
    imf_total = sum.("imf")
    national_total = sum.("retained")

    national_part =
      rows
      |> Enum.filter(&(&1["source"] == "national"))
      |> Enum.map(& &1["retained"])
      |> Enum.sum()

    pending_rows = Enum.filter(rows, &is_number(&1["pending"]))

    after_review =
      national_total +
        Enum.reduce(pending_rows, 0, fn r, acc ->
          acc + r["pending"] - (r["retained"] || 0)
        end)

    %{
      "year" => year,
      "imf_total" => round1(imf_total),
      "national_total" => round1(national_total),
      "national_share_pct" => share(national_part, national_total),
      "gap_pct" => gap_pct(national_total, imf_total),
      "counted" => Enum.count(rows, &(&1["source"] == "national")),
      "fallback" => Enum.count(rows, &(&1["source"] == "imf")),
      "missing" => for(r <- rows, r["source"] == "none", do: r["code"]),
      "pending" => for(r <- pending_rows, do: r["code"]),
      "pending_share_pct" =>
        share(Enum.reduce(pending_rows, 0, &(&1["pending"] + &2)), after_review),
      "after_review_total" => if(pending_rows != [], do: round1(after_review)),
      "after_review_gap_pct" => if(pending_rows != [], do: gap_pct(after_review, imf_total)),
      "rows" => rows
    }
  end

  defp imf_series do
    Repo.query!("""
    SELECT area_code, json_extract(doc, '$.series')
    FROM profiles WHERE json_extract(doc, '$.kind') = 'country'
    """).rows
    |> Map.new(fn [code, json] -> {code, Jason.decode!(json || "{}")} end)
  end

  defp at(nil, _year), do: nil

  defp at(series, year) when is_list(series) do
    case Enum.at(series, year - @first) do
      v when is_number(v) -> v * 1.0
      _ -> nil
    end
  end

  defp gap_pct(v, imf) when is_number(v) and is_number(imf) and imf != 0,
    do: Float.round((v / imf - 1) * 100, 1)

  defp gap_pct(_v, _imf), do: nil

  defp share(_part, total) when total == 0, do: nil
  defp share(part, total), do: Float.round(part / total * 100, 1)

  defp round1(v) when is_number(v), do: Float.round(v * 1.0, 1)

  defp to_float(nil), do: nil
  defp to_float(s), do: SyliAtlas.National.Verify.to_float(s)
end
