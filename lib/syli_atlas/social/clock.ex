defmodule SyliAtlas.Social.Clock do
  @moduledoc """
  Paris time for the posting schedule: Buffer's slots are set in
  Europe/Paris (10:00, 14:00, 19:00 on weekdays) and the admin shows them
  so. No time zone database in the app: the European summer time rule is
  enough (last Sunday of March to last Sunday of October, 01:00 UTC).
  """

  @doc "The Paris wall clock of a UTC instant, as a NaiveDateTime."
  def paris(%DateTime{} = utc),
    do: utc |> DateTime.to_naive() |> NaiveDateTime.add(offset(utc), :second)

  @doc "The UTC instant of a Paris wall clock time."
  def utc(%NaiveDateTime{} = local) do
    # The offset of the instant one hour earlier is right except within the
    # hour of the change, when no post is ever scheduled (01:00–03:00).
    guess = DateTime.from_naive!(NaiveDateTime.add(local, -3600, :second), "Etc/UTC")
    local |> NaiveDateTime.add(-offset(guess), :second) |> DateTime.from_naive!("Etc/UTC")
  end

  @doc "Seconds ahead of UTC in Paris at that instant (3600 or 7200)."
  def offset(%DateTime{year: year} = utc) do
    start = summer_change(year, 3)
    stop = summer_change(year, 10)

    if DateTime.compare(utc, start) != :lt and DateTime.compare(utc, stop) == :lt,
      do: 7200,
      else: 3600
  end

  # The last Sunday of the month, 01:00 UTC.
  defp summer_change(year, month) do
    last = Date.new!(year, month, Date.days_in_month(Date.new!(year, month, 1)))
    sunday = Date.add(last, -rem(Date.day_of_week(last), 7))
    DateTime.new!(sunday, ~T[01:00:00], "Etc/UTC")
  end

  @days ~w(lun. mar. mer. jeu. ven. sam. dim.)
  @months ~w(janv. févr. mars avr. mai juin juil. août sept. oct. nov. déc.)

  @doc "« mer. 18 nov. à 14:00 » (Paris time)."
  def label(nil), do: nil

  def label(%DateTime{} = utc) do
    local = paris(utc)
    "#{day_label(NaiveDateTime.to_date(local))} à #{Calendar.strftime(local, "%H:%M")}"
  end

  @doc "« mer. 18 nov. »"
  def day_label(%Date{} = d),
    do: "#{Enum.at(@days, Date.day_of_week(d) - 1)} #{d.day} #{Enum.at(@months, d.month - 1)}"

  @doc "« mer. 18 »"
  def short_day(%Date{} = d), do: "#{Enum.at(@days, Date.day_of_week(d) - 1)} #{d.day}"
end
