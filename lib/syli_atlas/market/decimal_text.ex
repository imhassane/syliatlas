defmodule SyliAtlas.Market.DecimalText do
  @moduledoc """
  An exact decimal stored as TEXT. SQLite would turn a NUMERIC column into
  a float, so prices are kept as their written form ("25500.00") and read
  back as `Decimal`.
  """
  use Ecto.Type

  def type, do: :string

  def cast(nil), do: {:ok, nil}
  def cast(%Decimal{} = d), do: {:ok, d}
  def cast(n) when is_integer(n), do: {:ok, Decimal.new(n)}
  def cast(n) when is_float(n), do: {:ok, Decimal.from_float(n)}

  def cast(s) when is_binary(s) do
    case Decimal.parse(String.trim(s)) do
      {d, ""} -> {:ok, d}
      _ -> :error
    end
  end

  def cast(_), do: :error

  def dump(nil), do: {:ok, nil}
  def dump(%Decimal{} = d), do: {:ok, Decimal.to_string(d, :normal)}

  def dump(other) do
    case cast(other) do
      {:ok, d} -> dump(d)
      :error -> :error
    end
  end

  def load(nil), do: {:ok, nil}
  def load(s) when is_binary(s), do: cast(s)
  def load(n) when is_number(n), do: cast(n)
end
