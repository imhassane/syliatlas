defmodule SyliAtlas.Market.RawStoreTest do
  use ExUnit.Case, async: false
  alias SyliAtlas.Market.RawStore.R2

  setup do
    Application.put_env(:syli_atlas, R2,
      account_id: "acc",
      access_key_id: "AKID",
      secret_access_key: "secret",
      bucket: "raw",
      req_options: [plug: {Req.Test, R2}, retry: false]
    )

    on_exit(fn -> Application.delete_env(:syli_atlas, R2) end)
  end

  test "puts and gets objects on R2 with a signed S3 request" do
    Req.Test.stub(R2, fn conn ->
      assert conn.host == "acc.r2.cloudflarestorage.com"
      assert conn.request_path == "/raw/market/x.json"
      assert [auth] = Plug.Conn.get_req_header(conn, "authorization")
      assert auth =~ "AWS4-HMAC-SHA256 Credential=AKID/"
      assert auth =~ "/auto/s3/aws4_request"

      case conn.method do
        "PUT" -> Plug.Conn.send_resp(conn, 200, "")
        "GET" -> Plug.Conn.send_resp(conn, 200, ~s({"ok":true}))
      end
    end)

    assert :ok = R2.put("market/x.json", ~s({"ok":true}), "application/json")
    assert {:ok, ~s({"ok":true})} = R2.get("market/x.json")
  end

  test "reports a refused write" do
    Req.Test.stub(R2, &Plug.Conn.send_resp(&1, 403, "denied"))
    assert {:error, {:http_status, 403}} = R2.put("market/y.json", "{}", "application/json")
  end
end
