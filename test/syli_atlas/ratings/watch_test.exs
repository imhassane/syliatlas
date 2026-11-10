defmodule SyliAtlas.Ratings.WatchTest do
  use SyliAtlas.DataCase, async: false

  alias SyliAtlas.Ratings
  alias SyliAtlas.Ratings.{Review, Text, Watch, WatchItem}

  @article """
  <html><body><nav>menu</nav><article><h1>Fitch upgrades Côte d'Ivoire</h1>
  <p>Fitch Ratings has upgraded Côte d&#8217;Ivoire&#8217;s long-term foreign-currency issuer default rating to &#x27;BBB-&#x27; from &#x27;BB&#x27; with a stable outlook, the agency said on Friday.</p>
  <p>The agency cited strong growth and fiscal consolidation, among other reasons that are described at length in the rest of this article about the West African country and its economy.</p>
  </article></body></html>
  """

  setup do
    SyliAtlas.Geo.seed_areas!()
    Ratings.seed!()
    now = Calendar.strftime(DateTime.utc_now(), "%a, %d %b %Y %H:%M:%S GMT")

    rss = """
    <?xml version="1.0"?><rss version="2.0"><channel><title>t</title>
    <item><title><![CDATA[Fitch upgrades Côte d'Ivoire to investment grade]]></title>
    <link>https://news.test/civ</link><description>Rating upgrade</description><pubDate>#{now}</pubDate></item>
    <item><title>Football: results of the weekend</title><link>https://news.test/foot</link><pubDate>#{now}</pubDate></item>
    </channel></rss>
    """

    Req.Test.stub(Watch, fn conn ->
      case conn.host do
        "feeds.test" -> Plug.Conn.send_resp(conn, 200, rss)
        "news.test" -> Plug.Conn.send_resp(conn, 200, @article)
      end
    end)

    Req.Test.stub(SyliAtlas.Ratings.Extractor, fn conn ->
      Req.Test.json(conn, %{
        "content" => [
          %{
            "type" => "tool_use",
            "name" => "record_decisions",
            "input" => %{
              "decisions" => [
                %{
                  "country_code" => "CIV",
                  "agency" => "fitch",
                  "rating" => "BBB-",
                  "outlook" => "stable",
                  "action_date" => "2026-11-06",
                  "action_type" => "upgrade",
                  "currency" => "foreign",
                  "is_new" => true,
                  "excerpt" =>
                    "Fitch Ratings has upgraded Côte d’Ivoire’s long-term foreign-currency issuer default rating to 'BBB-' from 'BB'"
                },
                %{
                  "country_code" => "SEN",
                  "agency" => "sp",
                  "rating" => "B",
                  "action_type" => "downgrade",
                  "currency" => "foreign",
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

  test "keeps relevant items, and only decisions whose excerpt is in the article" do
    assert %{collected: 1, read: 1, proposals: 1} = Watch.run()
    assert [p] = Review.list("pending")
    assert {p.country_code, p.agency, p.rating, p.origin} == {"CIV", "fitch", "BBB-", "watch"}
    assert p.article_url == "https://news.test/civ"
    assert "big_jump" not in p.warnings
    assert [%WatchItem{status: "extracted"}] = SyliAtlas.Repo.all(WatchItem)
    assert Watch.last_run()

    # Each item is read once.
    assert %{collected: 0, read: 0} = Watch.run()
  end

  test "relevance needs an agency, a rating word and an African country" do
    countries = %{"CIV" => "Cote d'Ivoire / Côte d'Ivoire", "KEN" => "Kenya / Kenya"}
    assert Watch.relevant?("Moody's relève la note du Kenya", countries)
    refute Watch.relevant?("Kenya wins the marathon", countries)
    refute Watch.relevant?("Fitch upgrades France", countries)
  end

  test "RSS dates and HTML entities" do
    assert Text.rfc1123("Tue, 10 Nov 2026 10:56:45 GMT") == ~U[2026-11-10 10:56:45Z]

    assert Text.html_to_text("<p>C&ocirc;te&nbsp;d&#8217;Ivoire</p><script>x()</script>") ==
             "Côte d’Ivoire"
  end
end
