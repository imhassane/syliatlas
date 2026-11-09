defmodule SyliAtlasWeb.Design.ContrastTest do
  @moduledoc """
  Every color pair the pages use, read from the tokens in
  `assets/css/base.css`, in the light and the dark theme (WCAG 2.2 AA):
  4.5:1 for text, 3:1 for control edges and chart marks.
  """
  use ExUnit.Case, async: true

  @css File.read!(Path.expand("../../../assets/css/base.css", __DIR__))

  @text [
    # body text and muted text on every surface
    {"ink", "page"},
    {"ink", "card"},
    {"ink", "alt"},
    {"ink", "muted"},
    {"ink", "accent-bg"},
    {"ink-muted", "page"},
    {"ink-muted", "card"},
    {"ink-muted", "alt"},
    {"ink-muted", "muted"},
    {"ink-subtle", "page"},
    {"ink-subtle", "card"},
    {"ink-subtle", "alt"},
    # links, eyebrows, the current row
    {"accent-text", "page"},
    {"accent-text", "card"},
    {"accent-text", "alt"},
    {"accent-text", "accent-bg"},
    # rises and falls, on cards and on the highlighted row
    {"success-ink", "card"},
    {"success-ink", "alt"},
    {"success-ink", "accent-bg"},
    {"success-ink", "success-bg"},
    {"signal-text", "card"},
    {"signal-text", "alt"},
    {"signal-text", "accent-bg"},
    {"warning-ink", "warning-bg"},
    # the navy band
    {"on-deep", "deep"},
    {"on-deep-muted", "deep"},
    {"on-deep-muted", "deep-raised"},
    {"accent-on-deep", "deep"},
    {"accent-on-deep", "deep-raised"},
    # filled buttons, the current page of a pager, the skip link
    {"#ffffff", "accent"},
    {"page", "ink"}
  ]

  @graphics [
    # edges of fields, selects, secondary buttons, the filters button
    {"border-input", "page"},
    {"border-input", "card"},
    # chart lines and bars
    {"c1", "card"},
    {"c2", "card"},
    {"c3", "card"},
    {"c4", "card"},
    {"c5", "card"},
    {"c6", "card"},
    {"signal", "card"},
    {"accent", "page"},
    # region colours (lines, dots, the regions map)
    {"r-north_africa", "card"},
    {"r-west_africa", "card"},
    {"r-central_africa", "card"},
    {"r-east_africa", "card"},
    {"r-southern_africa", "card"},
    # the selected country's outline on the map
    {"map-sel", "seq-2"},
    {"map-sel", "bad-2"}
  ]

  for theme <- [:light, :dark] do
    describe "#{theme} theme" do
      for {fg, bg} <- @text do
        test "text #{fg} on #{bg}" do
          assert_ratio(unquote(theme), unquote(fg), unquote(bg), 4.5)
        end
      end

      for {fg, bg} <- @graphics do
        test "mark #{fg} on #{bg}" do
          assert_ratio(unquote(theme), unquote(fg), unquote(bg), 3.0)
        end
      end
    end
  end

  defp assert_ratio(theme, fg, bg, min) do
    tokens = tokens(theme)
    a = color(tokens, fg)
    b = color(tokens, bg)
    ratio = ratio(a, b)

    assert ratio >= min,
           "#{theme}: #{fg} (#{a}) on #{bg} (#{b}) is #{Float.round(ratio, 2)}:1, needs #{min}:1"
  end

  # Light tokens are on :root; dark ones override them.
  defp tokens(:light), do: block(":root")
  defp tokens(:dark), do: Map.merge(block(":root"), block(~s([data-theme="dark"])))

  defp block(selector) do
    [_, body] = Regex.run(~r/#{Regex.escape(selector)}\s*\{([^}]*)\}/, @css)

    ~r/--([a-z0-9_-]+):\s*(#[0-9a-fA-F]{6})/
    |> Regex.scan(body)
    |> Map.new(fn [_, name, hex] -> {name, String.downcase(hex)} end)
  end

  defp color(_tokens, "#" <> _ = hex), do: hex
  defp color(tokens, name), do: Map.fetch!(tokens, name)

  defp ratio(a, b) do
    {l1, l2} = Enum.min_max([luminance(a), luminance(b)])
    (l2 + 0.05) / (l1 + 0.05)
  end

  defp luminance("#" <> hex) do
    [r, g, b] =
      for <<c::binary-size(2) <- hex>> do
        v = String.to_integer(c, 16) / 255
        if v <= 0.03928, do: v / 12.92, else: :math.pow((v + 0.055) / 1.055, 2.4)
      end

    0.2126 * r + 0.7152 * g + 0.0722 * b
  end
end
