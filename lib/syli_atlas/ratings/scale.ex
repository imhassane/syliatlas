defmodule SyliAtlas.Ratings.Scale do
  @moduledoc """
  One scale for the three agencies, from 1 (default) to 22 (AAA / Aaa).
  BBB− and Baa3 are 13, the lowest step of the investment grade.

  The common scale and the verdict bands are Syli Atlas's reading of the
  categories the agencies define; pages say so next to them.
  """

  @scores %{
    "AAA" => 22,
    "AA+" => 21,
    "AA" => 20,
    "AA-" => 19,
    "A+" => 18,
    "A" => 17,
    "A-" => 16,
    "BBB+" => 15,
    "BBB" => 14,
    "BBB-" => 13,
    "BB+" => 12,
    "BB" => 11,
    "BB-" => 10,
    "B+" => 9,
    "B" => 8,
    "B-" => 7,
    "CCC+" => 6,
    "CCC" => 5,
    "CCC-" => 4,
    "CC" => 3,
    "C" => 2,
    "SD" => 1,
    "RD" => 1,
    "D" => 1,
    "Aaa" => 22,
    "Aa1" => 21,
    "Aa2" => 20,
    "Aa3" => 19,
    "A1" => 18,
    "A2" => 17,
    "A3" => 16,
    "Baa1" => 15,
    "Baa2" => 14,
    "Baa3" => 13,
    "Ba1" => 12,
    "Ba2" => 11,
    "Ba3" => 10,
    "B1" => 9,
    "B2" => 8,
    "B3" => 7,
    "Caa1" => 6,
    "Caa2" => 5,
    "Caa3" => 4,
    "Ca" => 3
  }

  @labels %{
    22 => "AAA",
    21 => "AA+",
    20 => "AA",
    19 => "AA−",
    18 => "A+",
    17 => "A",
    16 => "A−",
    15 => "BBB+",
    14 => "BBB",
    13 => "BBB−",
    12 => "BB+",
    11 => "BB",
    10 => "BB−",
    9 => "B+",
    8 => "B",
    7 => "B−",
    6 => "CCC+",
    5 => "CCC",
    4 => "CCC−",
    3 => "CC",
    2 => "C",
    1 => "D"
  }

  # Lower bound of each band on the common scale, best first.
  @bands [
    {"investment", 12.5},
    {"speculative", 9.5},
    {"highly_speculative", 6.5},
    {"substantial_risk", 3.5},
    {"default", 0}
  ]

  @investment_grade 13

  def investment_grade, do: @investment_grade
  def max, do: 22
  def bands, do: Enum.map(@bands, &elem(&1, 0))

  @doc "Typed minus signs and spaces removed: « BB− » → « BB- »."
  def normalize(nil), do: nil
  def normalize(rating), do: rating |> String.trim() |> String.replace("−", "-")

  @doc "Position on the common scale, nil for an unknown symbol."
  def score(nil), do: nil
  def score(rating), do: Map.get(@scores, normalize(rating))

  @doc "A rating as printed: with a true minus sign."
  def display(nil), do: nil
  def display(rating), do: String.replace(rating, "-", "−")

  @doc "Half-up rounding, so 13.5 is 14 and 6.5 is 7."
  def round_score(value) when is_number(value), do: trunc(Float.floor(value / 1 + 0.5))

  @doc "The S&P / Fitch symbol of a position (or of an average) on the scale."
  def label(value) when is_number(value),
    do: Map.fetch!(@labels, value |> round_score() |> max(1) |> min(22))

  @doc "The verdict band of an average on the common scale."
  def band(value) when is_number(value) do
    Enum.find_value(@bands, fn {band, low} -> if value >= low, do: band end)
  end

  @doc "Notches between an average and the investment grade (negative: above it)."
  def notches_to_investment(value) when is_number(value),
    do: @investment_grade - round_score(value)
end
