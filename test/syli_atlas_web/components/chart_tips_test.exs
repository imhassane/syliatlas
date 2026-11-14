defmodule SyliAtlasWeb.ChartTipsTest do
  @moduledoc """
  The tooltip data written into each chart (Charts.tips/2,
  MarketComponents.index_chart/1): every year readable on hover, touch and
  keyboard, formatted for the locale, with its status, and a reader that
  stays hidden without JavaScript.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias SyliAtlasWeb.{Charts, MarketComponents}

  # Côte d'Ivoire, GDP in billions of current dollars (IMF, October 2026).
  @gdp [
    45.8,
    48.4,
    52.5,
    58.5,
    60.4,
    63.1,
    72.8,
    71.1,
    80.8,
    87.1,
    99.9,
    110.4,
    119.5,
    129.4,
    141.0,
    153.6
  ]

  defp render_chart(opts \\ []) do
    Gettext.put_locale(SyliAtlasWeb.Gettext, Keyword.get(opts, :locale, "fr"))

    render_component(
      &Charts.line_chart/1,
      Keyword.merge(
        [
          id: "area-chart",
          indicator: "gdp_usd_bn",
          from: 2020,
          to: 2025,
          estimate_from: 2025,
          locale: "fr",
          label: "PIB de la Côte d'Ivoire",
          source: "Source : FMI, Perspectives de l'économie mondiale (octobre 2026)",
          series: [%{id: "CIV", name: "Côte d'Ivoire", color: "--c1", values: @gdp, strong: true}]
        ],
        opts
      )
    )
  end

  defp tips(html) do
    doc = LazyHTML.from_fragment(html)

    doc
    |> LazyHTML.query("[data-chart-tips]")
    |> LazyHTML.attribute("data-chart-tips")
    |> Enum.map(&Jason.decode!/1)
  end

  test "both drawings (wide and narrow) carry every year, 2015 to 2030" do
    [wide, narrow] = tips(render_chart())

    for t <- [wide, narrow] do
      assert Enum.map(t["points"], & &1["year"]) == Enum.to_list(2015..2030)
      assert t["anchor"] == "area-chart-figure"
      assert t["from"] == 2020
    end

    assert wide["w"] == 760 and narrow["w"] == 360
  end

  test "2026 shows its value, status, change and source, in French" do
    [t | _] = tips(render_chart())
    p = Enum.find(t["points"], &(&1["year"] == 2026))

    assert p["status"] == "Projection"
    assert p["kind"] == "projection"
    assert [%{"name" => "Côte d'Ivoire", "text" => text, "color" => "--c1", "y" => y}] = p["rows"]
    assert text =~ ~r/^110,4\s?Md\$$/u
    assert is_float(y)
    assert p["change"] == "Côte d'Ivoire : +10,5 % sur un an"
    assert p["pick"] == "Afficher 2026 dans les chiffres"
    assert p["valuetext"] == "2026, projection : Côte d'Ivoire " <> text
    assert t["source"] =~ "FMI"
  end

  test "status follows the estimate year" do
    [t | _] = tips(render_chart())
    status = Map.new(t["points"], &{&1["year"], &1["kind"]})

    assert status[2024] == "data"
    assert status[2025] == "estimate"
    assert status[2030] == "projection"
  end

  test "a year at or before the reference year cannot become the end year" do
    [t | _] = tips(render_chart())
    picks = Map.new(t["points"], &{&1["year"], &1["pick"]})

    assert picks[2020] == nil
    assert picks[2015] == nil
    assert picks[2021] =~ "2021"
  end

  test "pick: false (embeds) offers no end year at all" do
    [t | _] = tips(render_chart(pick: false))
    assert Enum.all?(t["points"], &is_nil(&1["pick"]))
  end

  test "the slider starts on the end year and stays hidden until JavaScript runs" do
    html = render_chart(to: 2026)
    doc = LazyHTML.from_fragment(html)
    [reader | _] = LazyHTML.query(doc, ".chart-reader") |> Enum.to_list()

    assert LazyHTML.attribute(reader, "role") == ["slider"]
    assert LazyHTML.attribute(reader, "hidden") == [""]
    assert LazyHTML.attribute(reader, "tabindex") == ["0"]
    assert LazyHTML.attribute(reader, "aria-valuemin") == ["0"]
    assert LazyHTML.attribute(reader, "aria-valuemax") == ["15"]
    assert LazyHTML.attribute(reader, "aria-valuenow") == ["11"]
    assert [label] = LazyHTML.attribute(reader, "aria-label")
    assert label =~ "Lire le graphique année par année"
    assert [text] = LazyHTML.attribute(reader, "aria-valuetext")
    assert text =~ "2026, projection"

    # the tooltip itself is empty and hidden: no stray content without JS
    assert LazyHTML.query(doc, ".chart-tip[hidden]") |> Enum.count() == 2
  end

  test "a series without a value that year gets no dot, and n.d. in words" do
    values = Enum.take(@gdp, 11) ++ List.duplicate(nil, 5)

    [t | _] =
      tips(
        render_chart(
          series: [
            %{id: "CIV", name: "Côte d'Ivoire", color: "--c1", values: @gdp, strong: true},
            %{id: "SEN", name: "Sénégal", color: "--c2", values: values}
          ]
        )
      )

    p = Enum.find(t["points"], &(&1["year"] == 2027))
    [_, sen] = p["rows"]
    assert sen["y"] == nil
    assert sen["text"] == "n.d."
  end

  test "English pages read in English" do
    [t | _] = tips(render_chart(locale: "en"))
    p = Enum.find(t["points"], &(&1["year"] == 2025))

    assert p["status"] == "Estimate"
    assert p["pick"] == "Show 2025 in the figures"
    assert p["change"] =~ "over one year"
  end

  test "the market chart reads session by session, with the source's credit" do
    Gettext.put_locale(SyliAtlasWeb.Gettext, "fr")

    html =
      render_component(&MarketComponents.index_chart/1,
        id: "index-chart",
        history: [["2026-11-06", "8000"], ["2026-11-09", "8080"]],
        label: "BRVM Composite",
        locale: "fr",
        name: "BRVM Composite",
        sources: [%{"code" => "mansa", "rank" => 1}]
      )

    [t] = tips(html)
    [first, last] = t["points"]

    assert first["change"] == nil
    assert last["change"] =~ "+1,00"
    assert [%{"name" => "BRVM Composite"}] = last["rows"]
    assert t["start"] == 1
    assert t["source"] =~ "MansaAPI"
    assert t["source"] =~ "pas de cours en direct"
    assert Enum.all?(t["points"], &is_nil(&1["pick"]))
    assert html =~ ~s(role="slider")
  end
end
