defmodule SyliAtlas.CdnTest do
  use SyliAtlas.DataCase, async: false
  use Oban.Testing, repo: SyliAtlas.Repo, engine: Oban.Engines.Lite

  alias SyliAtlas.Cdn

  setup do
    previous = Application.get_env(:syli_atlas, Cdn)
    on_exit(fn -> Application.put_env(:syli_atlas, Cdn, previous) end)
    :ok
  end

  defp configure do
    Application.put_env(
      :syli_atlas,
      Cdn,
      Keyword.merge(Application.get_env(:syli_atlas, Cdn, []),
        zone_id: "zone123",
        api_token: "token-abc"
      )
    )
  end

  test "without the zone and the token, nothing is called" do
    refute Cdn.configured?()
    assert Cdn.purge_api() == :skipped
    assert Cdn.purge_api_later() == :skipped
    refute_enqueued(worker: SyliAtlas.Workers.CachePurgeWorker)
  end

  test "purges the API answers by prefix, with the token" do
    configure()
    test = self()

    Req.Test.stub(Cdn, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      send(
        test,
        {:purge, conn.request_path, Plug.Conn.get_req_header(conn, "authorization"),
         Jason.decode!(body)}
      )

      Req.Test.json(conn, %{"success" => true, "errors" => [], "result" => %{"id" => "zone123"}})
    end)

    assert Cdn.purge_api() == :ok
    assert_received {:purge, "/client/v4/zones/zone123/purge_cache", ["Bearer token-abc"], body}
    assert body == %{"prefixes" => [SyliAtlasWeb.Endpoint.host() <> "/api/v1/"]}
  end

  test "a refused purge is an error, retried by the worker" do
    configure()

    Req.Test.stub(Cdn, fn conn ->
      conn
      |> Plug.Conn.put_status(403)
      |> Req.Test.json(%{
        "success" => false,
        "errors" => [%{"code" => 10_000, "message" => "Authentication error"}]
      })
    end)

    assert {:error, {:http, 403}} = Cdn.purge_api()
    assert {:error, _} = perform_job(SyliAtlas.Workers.CachePurgeWorker, %{})
  end

  test "a new publication queues a purge" do
    configure()
    SyliAtlas.Fixtures.load_snapshot!()
    assert_enqueued(worker: SyliAtlas.Workers.CachePurgeWorker)
  end
end
