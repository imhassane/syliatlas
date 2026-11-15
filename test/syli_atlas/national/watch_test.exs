defmodule SyliAtlas.National.WatchTest do
  use SyliAtlas.DataCase, async: false

  alias SyliAtlas.National.{RebasingExtractor, Rebasings, Watch, WatchItem}

  @article """
  <html><body><article><h1>Ghana rebases its economy</h1>
  <p>The Ghana Statistical Service on Tuesday published GDP figures with 2023 as the new base year, replacing 2013, which lifted the size of the economy by 24.5 percent.</p>
  <p>The rebasing reflects the growth of mobile money and services since the last exercise, the statistician said in Accra, adding that ratios to GDP would be revised.</p>
  </article></body></html>
  """

  setup do
    SyliAtlas.Fixtures.load_snapshot!()
    now = Calendar.strftime(DateTime.utc_now(), "%a, %d %b %Y %H:%M:%S GMT")

    rss = """
    <?xml version="1.0"?><rss version="2.0"><channel><title>t</title>
    <item><title>Ghana rebases GDP, economy 24.5% bigger</title>
    <link>https://news.test/gha</link><description>New base year</description><pubDate>#{now}</pubDate></item>
    <item><title>Ghana: cocoa prices rise</title><link>https://news.test/cocoa</link><pubDate>#{now}</pubDate></item>
    </channel></rss>
    """

    Req.Test.stub(Watch, fn conn ->
      case conn.host do
        "feeds.test" -> Plug.Conn.send_resp(conn, 200, rss)
        "news.test" -> Plug.Conn.send_resp(conn, 200, @article)
      end
    end)

    Req.Test.stub(RebasingExtractor, fn conn ->
      Req.Test.json(conn, %{
        "content" => [
          %{
            "type" => "tool_use",
            "name" => "record_rebasings",
            "input" => %{
              "rebasings" => [
                %{
                  "country_code" => "GHA",
                  "announced_on" => "2026-11-10",
                  "old_base" => "2013",
                  "new_base" => "2023",
                  "level_change_pct" => 24.5,
                  "institution" => "Ghana Statistical Service",
                  "is_new" => true,
                  "excerpt" =>
                    "published GDP figures with 2023 as the new base year, replacing 2013, which lifted the size of the economy by 24.5 percent"
                },
                %{
                  "country_code" => "KEN",
                  "new_base" => "2024",
                  "is_new" => true,
                  "excerpt" => "A sentence that the article never contained at all."
                }
              ]
            }
          }
        ]
      })
    end)

    :ok
  end

  test "keeps relevant items, and only rebasings whose excerpt is in the article" do
    assert %{collected: 1, read: 1, proposals: 1} = Watch.run()
    assert [p] = Rebasings.proposed()

    assert {p.country_code, p.old_base, p.new_base, p.level_change_pct} ==
             {"GHA", "2013", "2023", "24.5"}

    assert p.origin == "watch"
    assert p.article_url == "https://news.test/gha"
    assert p.source_name =~ "Ghana Statistical Service"
    assert [%WatchItem{status: "extracted"}] = SyliAtlas.Repo.all(WatchItem)
    assert Watch.last_run()

    # Read once: a second run proposes nothing more.
    assert %{collected: 0, proposals: 0} = Watch.run()
  end

  test "an item must speak of a base year, of GDP and of an African country" do
    countries = %{"GHA" => "Ghana / Ghana"}
    assert Watch.relevant?("Ghana rebases its GDP", countries)
    assert Watch.relevant?("Le Ghana change l'année de base de son PIB", countries)
    refute Watch.relevant?("Ghana: cocoa prices rise", countries)
    refute Watch.relevant?("Argentina rebases its GDP", countries)
  end

  test "background and plans are dropped" do
    countries = %{"GHA" => "Ghana"}
    text = "Ghana plans to rebase its GDP to 2023 next year."

    base = %{
      "country_code" => "GHA",
      "new_base" => "2023",
      "excerpt" => "Ghana plans to rebase its GDP to 2023"
    }

    assert RebasingExtractor.check(Map.put(base, "is_new", false), text, countries) == []
    assert [_] = RebasingExtractor.check(Map.put(base, "is_new", true), text, countries)
  end
end
