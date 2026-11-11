defmodule SyliAtlas.DebtDistress do
  @moduledoc """
  Risk of external debt distress (low, moderate, high, in debt distress)
  from the IMF–World Bank debt sustainability analyses of low-income
  countries, as listed by the IMF ("List of LIC DSAs for PRGT-Eligible
  Countries"). A public assessment: shown with its date and a link to the
  list, never recomputed.

  Only countries eligible for the IMF's concessional lending (PRGT) are
  assessed this way; the others show "not assessed". The bundled file is
  `priv/data/debt_distress.json`; `checked` records whether it was checked
  against the PDF by hand. Kept in memory.
  """

  @key {__MODULE__, :document}
  @order %{"low" => 1, "moderate" => 2, "high" => 3, "distress" => 4}

  def path, do: Application.app_dir(:syli_atlas, "priv/data/debt_distress.json")

  def document do
    case :persistent_term.get(@key, nil) do
      nil ->
        doc =
          if File.exists?(path()),
            do: path() |> File.read!() |> Jason.decode!(),
            else: %{"countries" => %{}}

        :persistent_term.put(@key, doc)
        doc

      doc ->
        doc
    end
  end

  def for_country(code), do: document()["countries"][code]

  @doc "1 (low) to 4 (in debt distress), nil when not assessed."
  def level(nil), do: nil
  def level(%{"risk" => risk}), do: @order[risk]
end
