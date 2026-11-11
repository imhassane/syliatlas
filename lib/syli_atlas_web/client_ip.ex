defmodule SyliAtlasWeb.ClientIp do
  @moduledoc """
  The visitor's address, behind Railway and Cloudflare.

  - Railway's edge sets `X-Real-IP` on every request and replaces any copy
    the caller sends (https://docs.railway.com/networking/public-networking/specs-and-limits).
  - When the site is behind Cloudflare, that address is a Cloudflare one:
    the visitor is then in `CF-Connecting-IP`. That header is believed only
    when the request comes from a Cloudflare address, so nobody can choose
    their own address by sending it.
  - Without either header (local development, tests), the socket address.

  `key/1` groups IPv6 addresses by /64: one subscriber holds a whole /64.
  """
  import Bitwise

  # https://www.cloudflare.com/ips/ (checked on 11 Nov 2026).
  @cloudflare_cidrs ~w(
    173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22
    141.101.64.0/18 108.162.192.0/18 190.93.240.0/20 188.114.96.0/20
    197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13
    104.24.0.0/14 172.64.0.0/13 131.0.72.0/22
    2400:cb00::/32 2606:4700::/32 2803:f800::/32 2405:b500::/32
    2405:8100::/32 2a06:98c0::/29 2c0f:f248::/32
  )

  @cloudflare Enum.map(@cloudflare_cidrs, fn cidr ->
                [address, bits] = String.split(cidr, "/")
                {:ok, ip} = :inet.parse_address(String.to_charlist(address))
                {ip, String.to_integer(bits)}
              end)

  @doc "The visitor's address, as a tuple."
  @spec ip(Plug.Conn.t()) :: :inet.ip_address()
  def ip(conn) do
    peer = header_ip(conn, "x-real-ip") || conn.remote_ip

    with true <- cloudflare?(peer),
         visitor when not is_nil(visitor) <- header_ip(conn, "cf-connecting-ip") do
      visitor
    else
      _ -> peer
    end
  end

  @doc "A stable text key for counters: the IPv4 address, or the IPv6 /64."
  @spec key(Plug.Conn.t()) :: String.t()
  def key(conn), do: conn |> ip() |> key_for()

  @doc false
  def key_for({_, _, _, _} = ip), do: ip |> :inet.ntoa() |> to_string()

  def key_for({a, b, c, d, _, _, _, _}),
    do: {a, b, c, d, 0, 0, 0, 0} |> :inet.ntoa() |> to_string() |> Kernel.<>("/64")

  @doc "Whether an address belongs to Cloudflare."
  @spec cloudflare?(:inet.ip_address()) :: boolean()
  def cloudflare?(ip), do: Enum.any?(@cloudflare, fn {net, bits} -> within?(ip, net, bits) end)

  defp header_ip(conn, name) do
    with [value | _] <- Plug.Conn.get_req_header(conn, name),
         {:ok, ip} <- value |> String.split(",") |> hd() |> String.trim() |> parse() do
      ip
    else
      _ -> nil
    end
  end

  defp parse(text), do: :inet.parse_strict_address(String.to_charlist(text))

  defp within?(ip, net, bits) when tuple_size(ip) == tuple_size(net) do
    size = if tuple_size(ip) == 4, do: 32, else: 128
    mask = bnot((1 <<< (size - bits)) - 1) &&& (1 <<< size) - 1
    (to_int(ip) &&& mask) == (to_int(net) &&& mask)
  end

  defp within?(_, _, _), do: false

  defp to_int({a, b, c, d}), do: a <<< 24 ||| b <<< 16 ||| c <<< 8 ||| d

  defp to_int({_, _, _, _, _, _, _, _} = ip),
    do: ip |> Tuple.to_list() |> Enum.reduce(0, fn part, acc -> acc <<< 16 ||| part end)
end
