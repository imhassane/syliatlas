defmodule SyliAtlas.Admin.DailyDigestTest do
  use SyliAtlas.DataCase, async: false

  alias SyliAtlas.Admin.DailyDigest

  defp stub_plausible do
    Req.Test.stub(SyliAtlas.Plausible, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      body = Jason.decode!(raw)

      results =
        case body["dimensions"] do
          ["event:page"] ->
            [%{"dimensions" => ["/fr/afrique/commerce"], "metrics" => [40]}]

          ["visit:source"] ->
            [
              %{"dimensions" => ["Google"], "metrics" => [60]},
              %{"dimensions" => ["Direct / None"], "metrics" => [30]},
              %{"dimensions" => ["ChatGPT"], "metrics" => [6]},
              %{"dimensions" => ["Perplexity"], "metrics" => [4]}
            ]

          _ ->
            if body["date_range"] == ["2026-11-15", "2026-11-15"],
              do: [%{"metrics" => [80, 100, 300, 161]}],
              else: [%{"metrics" => [70, 80, 250, 120]}]
        end

      Req.Test.json(conn, %{"results" => results})
    end)
  end

  test "Paris day: winter and summer time" do
    assert DailyDigest.paris_today(~U[2026-11-16 23:30:00Z]) == ~D[2026-11-17]
    assert DailyDigest.paris_today(~U[2026-07-01 21:30:00Z]) == ~D[2026-07-01]
    assert DailyDigest.paris_today(~U[2026-07-01 22:30:00Z]) == ~D[2026-07-02]
  end

  test "the email: actions, audience compared with the week before, AI assistants grouped" do
    stub_plausible()
    data = DailyDigest.build(~D[2026-11-16])
    email = DailyDigest.email("admin@example.com", data)

    assert email.to == [{"", "admin@example.com"}]
    assert email.subject =~ "100 visites hier"
    text = email.text_body
    assert text =~ "Hier, 100 visites (+25 % sur une semaine)"
    assert text =~ "Assistants IA (ChatGPT, Perplexity, Claude…) : 10 (10 %)"
    assert text =~ "/fr/afrique/commerce : 40"
    assert text =~ "Durée moyenne : 2 min 41"
    assert email.html_body =~ "Point du jour"
  end

  test "without Plausible the email still goes, and says why the figures are missing" do
    Req.Test.stub(SyliAtlas.Plausible, &Plug.Conn.send_resp(&1, 401, "{}"))
    email = DailyDigest.email("admin@example.com", DailyDigest.build(~D[2026-11-16]))
    assert email.text_body =~ "Statistiques indisponibles"
    refute email.subject =~ "visites"
  end

  test "deltas" do
    assert DailyDigest.delta(125, 100) == "+25 %"
    assert DailyDigest.delta(80, 100) == "−20 %"
    assert DailyDigest.delta(5, 0) == nil
  end
end
