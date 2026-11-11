defmodule SyliAtlas.ResendDeliveryTest do
  # Emails through SyliAtlas.Mailer.Resend, against a local stand-in of
  # Resend's API: what production sends, without the network.
  use SyliAtlas.DataCase, async: false

  alias SyliAtlas.Mailer.Resend

  defmodule FakeResend do
    @behaviour Plug
    def init(test), do: test

    def call(conn, test) do
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      body = JSON.decode!(body)
      send(test, {:resend, conn.method, conn.request_path, conn.req_headers, body})

      {status, reply} =
        if body["to"] == ["refused@example.com"],
          do:
            {422,
             ~s({"statusCode":422,"name":"validation_error","message":"Invalid `to` field."})},
          else: {200, ~s({"id":"4ef9a417-02e9-4d39-ad75-9611e0fcc33c"})}

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(status, reply)
    end
  end

  setup do
    server =
      start_supervised!(
        {Bandit, plug: {FakeResend, self()}, port: 0, ip: :loopback, startup_log: false}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    {:ok, config: [api_key: "re_test", base_url: "http://127.0.0.1:#{port}"]}
  end

  test "an email goes to /emails with the key, text, HTML, headers as an object and the idempotency key",
       %{config: config} do
    email =
      "esi@example.com"
      |> SyliAtlas.Accounts.Emails.code("482913", "fr", false)
      |> Swoosh.Email.header("List-Unsubscribe", "<https://syliatlas.test/unsubscribe/x>")
      |> Swoosh.Email.header("List-Unsubscribe-Post", "List-Unsubscribe=One-Click")
      |> Swoosh.Email.put_private(:idempotency_key, "alert-delivery-7")

    assert {:ok, %{id: "4ef9a417-02e9-4d39-ad75-9611e0fcc33c"}} = Resend.deliver(email, config)

    assert_received {:resend, "POST", "/emails", headers, body}
    assert {"authorization", "Bearer re_test"} in headers
    assert {"idempotency-key", "alert-delivery-7"} in headers
    assert body["from"] =~ "Syli Atlas <"
    assert body["to"] == ["esi@example.com"]
    assert body["subject"] == "482 913 est votre code Syli Atlas"
    assert body["text"] =~ "    482 913"
    assert body["html"] =~ ~s(dir="ltr")

    assert body["headers"] == %{
             "List-Unsubscribe" => "<https://syliatlas.test/unsubscribe/x>",
             "List-Unsubscribe-Post" => "List-Unsubscribe=One-Click"
           }
  end

  test "a refusal comes back as an error, for Oban to retry or report", %{config: config} do
    email = SyliAtlas.Accounts.Emails.code("refused@example.com", "482913", "fr", false)
    assert {:error, {422, %{"name" => "validation_error"}}} = Resend.deliver(email, config)
  end

  test "an API key is required" do
    assert_raise ArgumentError, ~r/api_key/, fn -> Resend.validate_config([]) end
  end
end
