defmodule SyliAtlasWeb.MarketChartTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias SyliAtlasWeb.MarketComponents

  @history [["2026-11-10", "8012.5"], ["2026-11-11", "8034.0"]]

  test "the chart renders from two sessions on, labels placed under their grid line" do
    html =
      render_component(&MarketComponents.index_chart/1,
        id: "index-chart",
        history: @history,
        label: "Index",
        locale: "fr"
      )

    assert html =~ ~s(id="index-chart")

    for t <- MarketComponents.chart(@history).ticks do
      assert is_binary(t.y) and is_binary(t.label_y)
      assert String.to_float(t.label_y) == Float.round(String.to_float(t.y) + 4, 1)
      assert html =~ ~s(y="#{t.label_y}")
    end
  end
end
