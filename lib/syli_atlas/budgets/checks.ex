defmodule SyliAtlas.Budgets.Checks do
  @moduledoc """
  Automatic checks run on a proposed budget law before a human looks at it.
  They never block: each finding is shown in the admin, with its level
  (`"error"` or `"warning"`), so the reviewer knows what to look at.

    * the currency is the country's own;
    * revenue and expenditure are positive;
    * the dates follow each other (tabled ≤ voted ≤ promulgated ≤ published);
    * against the latest law of the country: a figure ten times larger or
      smaller (a lost or extra « 000 »), or a change of more than 40 %;
    * the share of GDP, when the IMF gives the GDP: expenditure outside
      2 %–80 % of GDP is suspicious;
    * the year is plausible (not more than two years away).
  """
  alias SyliAtlas.Economy.Currencies

  @doc "Findings for a proposal (any map with the law fields), as a list of maps."
  def run(p, opts \\ []) do
    p = if is_struct(p), do: Map.from_struct(p), else: p
    previous = Keyword.get(opts, :previous)
    gdp_local = Keyword.get(opts, :gdp_local)
    today = Keyword.get(opts, :today, Date.utc_today())

    [
      currency(p),
      positive(p, :revenue),
      positive(p, :expenditure),
      dates(p),
      year(p, today),
      against_previous(p, previous, :revenue),
      against_previous(p, previous, :expenditure),
      share_of_gdp(p, gdp_local)
    ]
    |> List.flatten()
  end

  @doc "True when a finding of level error is present."
  def errors?(checks), do: Enum.any?(checks, &(&1["level"] == "error"))

  defp finding(code, level, message),
    do: %{"code" => code, "level" => level, "message" => message}

  defp currency(%{country_code: c, currency: cur}) when is_binary(cur) do
    case Currencies.for_country(c) do
      %{code: ^cur} -> []
      %{code: expected} -> finding("currency", "error", "Devise #{cur}, attendue #{expected}")
      nil -> []
    end
  end

  defp currency(_), do: finding("currency", "warning", "Devise manquante")

  defp positive(p, field) do
    case Map.get(p, field) do
      nil ->
        finding(Atom.to_string(field), "warning", "#{label(field)} manquantes")

      %Decimal{} = d ->
        if Decimal.compare(d, 0) == :gt,
          do: [],
          else: finding(Atom.to_string(field), "error", "#{label(field)} nulles ou négatives")
    end
  end

  defp dates(p) do
    days =
      [p[:tabled_on], p[:voted_on], p[:promulgated_on], p[:published_on]]
      |> Enum.reject(&is_nil/1)

    if days == Enum.sort(days, Date),
      do: [],
      else: finding("dates", "error", "Dates dans le désordre (dépôt, vote, promulgation, JO)")
  end

  defp year(%{fiscal_year: y}, today) when is_integer(y) do
    if abs(y - today.year) > 2,
      do: finding("year", "warning", "Exercice #{y}, loin de l'année en cours"),
      else: []
  end

  defp year(_, _), do: finding("year", "warning", "Exercice manquant")

  defp against_previous(_p, nil, _field), do: []

  defp against_previous(p, previous, field) do
    with %Decimal{} = now <- Map.get(p, field),
         %Decimal{} = before <- Map.get(previous, field),
         true <- Decimal.compare(before, 0) == :gt do
      ratio = Decimal.div(now, before) |> Decimal.to_float()
      ref = "#{previous.fiscal_year} (#{kind_label(previous.kind)})"

      cond do
        ratio > 7 or ratio < 1 / 7 ->
          finding(
            "#{field}_scale",
            "error",
            "#{label(field)} #{times(ratio)} celles de #{ref} : un « 000 » perdu ou en trop ?"
          )

        abs(ratio - 1) > 0.4 ->
          finding(
            "#{field}_jump",
            "warning",
            "#{label(field)} #{pct(ratio)} par rapport à #{ref}"
          )

        true ->
          []
      end
    else
      _ -> []
    end
  end

  defp share_of_gdp(_p, nil), do: []

  defp share_of_gdp(p, gdp_local) when is_number(gdp_local) and gdp_local > 0 do
    case p[:expenditure] do
      %Decimal{} = d ->
        share = Decimal.to_float(d) / gdp_local * 100

        if share < 2 or share > 80,
          do:
            finding(
              "gdp_share",
              "warning",
              "Dépenses égales à #{Float.round(share, 1)} % du PIB (FMI) : unité à vérifier"
            ),
          else: []

      _ ->
        []
    end
  end

  defp share_of_gdp(_p, _), do: []

  defp label(:revenue), do: "Recettes"
  defp label(:expenditure), do: "Dépenses"

  defp kind_label("initial"), do: "initiale"
  defp kind_label("amending"), do: "rectificative"
  defp kind_label("settlement"), do: "règlement"
  defp kind_label("provisional"), do: "provisoire"
  defp kind_label(_), do: "?"

  defp times(r) when r >= 1, do: "#{round(r)} fois"
  defp times(r), do: "#{round(1 / r)} fois moins que"

  defp pct(r) do
    v = round((r - 1) * 100)
    if v > 0, do: "+#{v} %", else: "#{v} %"
  end
end
