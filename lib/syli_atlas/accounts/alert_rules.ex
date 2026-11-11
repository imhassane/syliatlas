defmodule SyliAtlas.Accounts.AlertRules do
  @moduledoc """
  When an alert fires. Pure functions: values, years and dates are passed in.

  A threshold fires when a new value crosses it, coming from the value the
  alert last saw: « goes below 5 % » fires once, when 5.3 becomes 4.8, not
  at every edition where it stays below. A value already past the threshold
  when the alert is created waits for it to come back and cross again.
  """

  @doc "Whether `current` crosses the threshold of `kind` coming from `previous`."
  @spec crossed?(String.t(), Decimal.t(), Decimal.t() | nil, Decimal.t() | nil) :: boolean()
  def crossed?(_kind, _threshold, nil, _current), do: false
  def crossed?(_kind, _threshold, _previous, nil), do: false

  def crossed?("indicator_below", threshold, previous, current),
    do: Decimal.gt?(previous, threshold) and not Decimal.gt?(current, threshold)

  def crossed?("indicator_above", threshold, previous, current),
    do: Decimal.lt?(previous, threshold) and not Decimal.lt?(current, threshold)

  @doc """
  The year a threshold watches: the current one, which an October edition
  projects and an April edition estimates or projects.
  """
  def watched_year(%Date{year: year}), do: year

  @doc "« estimate » or « projection » for a year of an edition coded 2026-10."
  def status(year, edition_code) do
    {edition_year, _} = Integer.parse(edition_code)

    cond do
      year >= edition_year -> "projection"
      year == edition_year - 1 -> "estimate"
      true -> "actual"
    end
  end

  @doc "Floats from the IMF become exact decimals, rounded as published (1 decimal)."
  def to_decimal(nil), do: nil

  def to_decimal(value) when is_float(value),
    do: value |> Decimal.from_float() |> Decimal.round(1)

  def to_decimal(value) when is_integer(value), do: Decimal.new(value)

  @doc "The week or month a digest covers, ending the day before `today`."
  def digest_period("monthly", today),
    do:
      {Date.add(Date.beginning_of_month(today), -1) |> Date.beginning_of_month(),
       Date.add(today, -1)}

  def digest_period(_weekly, today), do: {Date.add(today, -7), Date.add(today, -1)}

  @doc "Whether today is a digest day for this frequency (Monday; the 1st)."
  def digest_day?("weekly", today), do: Date.day_of_week(today) == 1
  def digest_day?("monthly", today), do: today.day == 1
  def digest_day?(_never, _today), do: false
end
