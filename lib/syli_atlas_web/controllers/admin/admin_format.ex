defmodule SyliAtlasWeb.Admin.Format do
  @moduledoc "Small French formatting helpers shared by the admin pages."

  @months ~w(janv. févr. mars avr. mai juin juil. août sept. oct. nov. déc.)

  @doc "« 6 nov. 2026 »; « 6 nov. » with `year: false`."
  def day(at, opts \\ [])
  def day(nil, _opts), do: "—"
  def day(%DateTime{} = at, opts), do: day(DateTime.to_date(at), opts)
  def day(%NaiveDateTime{} = at, opts), do: day(NaiveDateTime.to_date(at), opts)

  def day(%Date{} = d, opts) do
    base = "#{d.day} #{Enum.at(@months, d.month - 1)}"
    if Keyword.get(opts, :year, true), do: "#{base} #{d.year}", else: base
  end

  @doc "« 06:00 » for today, else « 6 nov. 06:00 » (UTC)."
  def when_(nil), do: "—"
  def when_(%NaiveDateTime{} = at), do: when_(DateTime.from_naive!(at, "Etc/UTC"))

  def when_(%DateTime{} = at) do
    time = Calendar.strftime(at, "%H:%M")
    if DateTime.to_date(at) == Date.utc_today(), do: time, else: "#{day(at, year: false)} #{time}"
  end

  @doc "A duration in milliseconds: « 210 ms », « 1,8 s », « 2 min 05 »."
  def duration(nil), do: "—"
  def duration(ms) when ms < 1000, do: "#{ms} ms"
  def duration(ms) when ms < 60_000, do: "#{decimal(ms / 1000, 1)} s"

  def duration(ms) do
    s = div(ms, 1000)
    "#{div(s, 60)} min #{String.pad_leading(to_string(rem(s, 60)), 2, "0")}"
  end

  @doc "French decimal with `places` digits: « 0,62 »."
  def decimal(nil, _places), do: "—"

  def decimal(n, places) when is_number(n),
    do:
      n |> Kernel.*(1.0) |> :erlang.float_to_binary(decimals: places) |> String.replace(".", ",")

  @doc "Thousands with a narrow space: « 1 357 »."
  def int(nil), do: "—"

  def int(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1 ")
    |> String.reverse()
  end

  @doc "Microseconds shown in milliseconds: « 0,62 ms »."
  def ms_from_us(nil), do: "—"
  def ms_from_us(us), do: decimal(us / 1000, 2) <> " ms"

  @doc "The label and pill class of an Oban job state."
  def job_state("completed"), do: {"Terminé", "pill-ok"}
  def job_state("executing"), do: {"En cours", "pill-info"}
  def job_state("available"), do: {"En attente", "pill-neutral"}
  def job_state("scheduled"), do: {"Planifié", "pill-neutral"}
  def job_state("retryable"), do: {"Nouvel essai", "pill-warn"}
  def job_state("discarded"), do: {"Échec", "pill-warn"}
  def job_state("cancelled"), do: {"Annulé", "pill-neutral"}
  def job_state(other), do: {other, "pill-neutral"}

  @indicators %{
    "real_gdp_growth" => "Croissance",
    "gdp_usd_bn" => "PIB (Md $)",
    "gdp_per_capita_usd" => "PIB par habitant",
    "gdp_per_capita_ppp" => "PIB par habitant (PPA)",
    "inflation" => "Inflation",
    "public_debt_pct_gdp" => "Dette publique",
    "population_m" => "Population",
    "fiscal_balance_pct_gdp" => "Solde budgétaire",
    "current_account_pct_gdp" => "Balance courante",
    "unemployment" => "Chômage"
  }

  def indicator(key), do: Map.get(@indicators, key, key)
end
