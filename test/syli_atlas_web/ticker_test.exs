defmodule SyliAtlasWeb.TickerTest do
  use SyliAtlasWeb.ConnCase, async: false

  alias SyliAtlas.MarketFixtures
  alias SyliAtlasWeb.Ticker

  defp doc(path), do: build_conn() |> get(path) |> html_response(200) |> LazyHTML.from_document()
  defp count(html, selector), do: html |> LazyHTML.query(selector) |> Enum.count()

  describe "indices" do
    test "keep only indices with a value, a change and no quality flag" do
      ok = %{"value" => "520.74", "change_pct" => "0.10", "flags" => %{"missing" => false}}

      overview = %{
        "exchanges" => [
          %{"exchange" => %{"code" => "brvm", "short_name" => "BRVM"}, "index" => ok},
          %{
            "exchange" => %{"code" => "jse", "short_name" => "JSE"},
            "index" => Map.put(ok, "flags", %{"suspect" => true})
          },
          %{
            "exchange" => %{"code" => "mse", "short_name" => "MSE"},
            "index" => Map.put(ok, "flags", %{"stale" => true})
          },
          %{
            "exchange" => %{"code" => "egx", "short_name" => "EGX"},
            "index" => %{"value" => nil, "change_pct" => nil, "flags" => %{"missing" => true}}
          },
          %{
            "exchange" => %{"code" => "use", "short_name" => "USE"},
            "index" => Map.put(ok, "change_pct", nil)
          }
        ]
      }

      assert [%{code: "brvm", name: "BRVM"}] = Ticker.indices(overview)
      assert Ticker.indices(nil) == []
    end
  end

  describe "ratings" do
    defp country(code, agencies),
      do: %{
        "code" => code,
        "name" => %{"fr" => code},
        "slug" => %{"fr" => code},
        "agencies" => agencies
      }

    defp decision(agency, action, date, check \\ false),
      do: %{
        "agency" => agency,
        "rating" => "B",
        "action_type" => action,
        "action_date" => date,
        "needs_check" => check
      }

    test "changes only, never a decision to check, newest first, at most ten" do
      doc = %{
        "countries" => %{
          "ZMB" => country("ZMB", [decision("moodys", "upgrade", "2026-10-30")]),
          "SEN" =>
            country("SEN", [
              decision("moodys", "downgrade", "2026-10-29"),
              decision("sp", "affirmed", "2026-11-01")
            ]),
          "BFA" => country("BFA", [decision("sp", "upgrade", "2026-11-06", true)]),
          "AGO" => country("AGO", [decision("moodys", "outlook_up", "2026-09-25")])
        }
      }

      assert Enum.map(Ticker.ratings(doc), &{&1.country, &1.action}) ==
               [{"ZMB", "upgrade"}, {"SEN", "downgrade"}, {"AGO", "outlook_up"}]

      many = %{
        "countries" =>
          Map.new(1..15, fn i ->
            code = "C#{i}"

            {code,
             country(code, [
               decision("fitch", "upgrade", "2026-10-#{String.pad_leading("#{i}", 2, "0")}")
             ])}
          end)
      }

      assert length(Ticker.ratings(many)) == 10
      assert hd(Ticker.ratings(many)).country == "C15"
    end
  end

  describe "pages" do
    setup do
      SyliAtlas.Fixtures.load_snapshot!()
      MarketFixtures.import!()
      :ok
    end

    test "public pages carry the band under the header, with the market credit" do
      for path <- ["/fr", "/fr/notations", "/fr/bourses", "/en"] do
        html = doc(path)
        assert count(html, "header.site-header + #site-ticker") == 1, path
        # Written twice for the loop; the copy is hidden and skipped by the keyboard.
        assert count(html, "#site-ticker .site-ticker-list") == 2
        assert count(html, ~s(#site-ticker .site-ticker-list[aria-hidden="true"])) == 1

        assert count(
                 html,
                 ~s|#site-ticker .site-ticker-list[aria-hidden="true"] a:not([tabindex="-1"])|
               ) == 0

        assert count(html, "#site-ticker-pause[hidden]") == 1
      end

      html = doc("/fr")
      assert count(html, ~s(#site-ticker a[href^="/fr/bourses/"])) > 0
      assert html |> LazyHTML.query(".site-ticker-credit") |> LazyHTML.text() =~ "fin de journée"
    end

    test "rating decisions link to the country's rating page" do
      ratings = Ticker.get().ratings
      assert ratings != []
      assert Enum.all?(ratings, &(&1.action != "affirmed"))
      html = doc("/fr")
      r = hd(ratings)
      assert count(html, ~s(#site-ticker a[href="/fr/notations/#{r.slug["fr"]}"])) >= 1
    end

    test "sign-in, account and unsubscribe pages have no band" do
      assert count(doc("/fr/connexion"), "#site-ticker") == 0
    end
  end
end
