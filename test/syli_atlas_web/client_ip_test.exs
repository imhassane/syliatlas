defmodule SyliAtlasWeb.ClientIpTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  alias SyliAtlasWeb.ClientIp

  defp conn(headers, remote_ip \\ {10, 0, 0, 1}) do
    Enum.reduce(headers, %{Plug.Test.conn(:get, "/api/v1/areas") | remote_ip: remote_ip}, fn {k,
                                                                                              v},
                                                                                             c ->
      put_req_header(c, k, v)
    end)
  end

  test "behind Cloudflare, the visitor is in CF-Connecting-IP" do
    conn = conn([{"x-real-ip", "172.70.10.20"}, {"cf-connecting-ip", "41.82.3.4"}])
    assert ClientIp.ip(conn) == {41, 82, 3, 4}
    assert ClientIp.key(conn) == "41.82.3.4"
  end

  test "CF-Connecting-IP sent by anyone else is ignored" do
    conn = conn([{"x-real-ip", "196.200.1.9"}, {"cf-connecting-ip", "8.8.8.8"}])
    assert ClientIp.ip(conn) == {196, 200, 1, 9}
  end

  test "without Railway's header, the socket address" do
    assert conn([], {127, 0, 0, 1}) |> ClientIp.key() == "127.0.0.1"

    assert conn([{"x-real-ip", "not an address"}], {127, 0, 0, 1}) |> ClientIp.key() ==
             "127.0.0.1"
  end

  test "IPv6 visitors share one counter per /64" do
    a = conn([{"x-real-ip", "2606:4700::1"}, {"cf-connecting-ip", "2c0f:fb50:1:2:aaaa::1"}])
    b = conn([{"x-real-ip", "2606:4700::1"}, {"cf-connecting-ip", "2c0f:fb50:1:2:bbbb::9"}])
    assert ClientIp.key(a) == ClientIp.key(b)
    assert ClientIp.key(a) == "2c0f:fb50:1:2::/64"
  end

  test "Cloudflare ranges" do
    assert ClientIp.cloudflare?({104, 16, 0, 1})
    assert ClientIp.cloudflare?({197, 234, 241, 1})
    refute ClientIp.cloudflare?({197, 234, 250, 1})
    assert ClientIp.cloudflare?({0x2A06, 0x98C7, 0, 0, 0, 0, 0, 1})
    refute ClientIp.cloudflare?({0x2A06, 0x98C8, 0, 0, 0, 0, 0, 1})
  end
end
