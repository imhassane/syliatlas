defmodule SyliAtlasWeb.SimulatorHTML do
  use SyliAtlasWeb, :html
  alias SyliAtlasWeb.{MarketComponents, SimulatorController}

  embed_templates "simulator_html/*"

  defdelegate money(x, currency, locale), to: SimulatorController
  defdelegate day(d, locale), to: SimulatorController
  defdelegate index_name(e), to: SimulatorController
  defdelegate signed(c, locale), to: SyliAtlasWeb.CurrencyController

  def tone(nil), do: "muted"
  def tone(c) when c > 0.05, do: "up"
  def tone(c) when c < -0.05, do: "down"
  def tone(_), do: "muted"

  def currency_label("USD"), do: gettext("dollars")
  def currency_label("EUR"), do: gettext("euros")
  def currency_label("CNY"), do: gettext("yuan")
  def currency_label(code), do: code

  def preset_label(:first), do: gettext("Since the start")
  def preset_label(n), do: ngettext("1 year", "%{count} years", n)

  @doc "Link to the simulator with one parameter changed."
  def sim_href(locale, query, key, value) do
    Paths.simulator(locale) <> "?" <> URI.encode_query(Map.put(query, key, value))
  end

  def whatsapp_href(text, url) do
    "https://wa.me/?" <> URI.encode_query(%{"text" => text <> " " <> url})
  end

  @w 720
  @h 260
  @pad_l 8
  @pad_r 8
  @pad_t 16
  @pad_b 28

  @doc """
  The curve of the placement as SVG geometry: the line, the area under it,
  the line of the amount put in, the year ticks and the extremes.
  """
  def chart(%{points: points, amount: amount}) when length(points) >= 2 do
    {d0, _} = hd(points)
    {d1, _} = List.last(points)
    span = max(Date.diff(d1, d0), 1)
    values = [amount | Enum.map(points, &elem(&1, 1))]
    lo = Enum.min(values)
    hi = Enum.max(values)
    {lo, hi} = if hi == lo, do: {lo * 0.9, hi * 1.1 + 1}, else: {lo, hi}
    margin = (hi - lo) * 0.06
    lo = max(lo - margin, 0)
    hi = hi + margin

    x = fn d -> @pad_l + Date.diff(d, d0) / span * (@w - @pad_l - @pad_r) end
    y = fn v -> @pad_t + (1 - (v - lo) / (hi - lo)) * (@h - @pad_t - @pad_b) end

    coords = Enum.map(points, fn {d, v} -> {r(x.(d)), r(y.(v))} end)
    line = "M" <> Enum.map_join(coords, " L", fn {a, b} -> "#{a},#{b}" end)
    {last_x, _} = List.last(coords)
    {first_x, _} = hd(coords)
    bottom = @h - @pad_b
    area = line <> " L#{last_x},#{bottom} L#{first_x},#{bottom} Z"

    year_step = if span > 365 * 8, do: 2, else: 1

    ticks =
      for year <- (d0.year + 1)..d1.year//1,
          rem(year, year_step) == 0,
          do: %{x: r(x.(Date.new!(year, 1, 1))), label: Integer.to_string(year)}

    {peak_d, peak_v} = Enum.max_by(points, &elem(&1, 1))
    {low_d, low_v} = Enum.min_by(points, &elem(&1, 1))

    %{
      w: @w,
      h: @h,
      bottom: bottom,
      line: line,
      area: area,
      base_y: r(y.(amount)),
      ticks: ticks,
      end_x: last_x,
      end_y: elem(List.last(coords), 1),
      peak: %{x: r(x.(peak_d)), y: r(y.(peak_v)), v: peak_v, d: peak_d},
      low: %{x: r(x.(low_d)), y: r(y.(low_v)), v: low_v, d: low_d},
      up?: elem(List.last(points), 1) >= amount
    }
  end

  def chart(_), do: nil

  defp r(f), do: Float.round(f * 1.0, 1)

  @doc "Width of a year's bar in the year table, out of the largest move."
  def bar_width(change, rows) do
    top = rows |> Enum.map(&abs(&1.change)) |> Enum.max(fn -> 1 end) |> max(1)
    Float.round(abs(change) / top * 100, 1)
  end
end
