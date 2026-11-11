defmodule SyliAtlas.Mailer.Resend do
  @moduledoc """
  Swoosh adapter for Resend's HTTP API (`POST /emails`), with Req.

  Ours rather than `Swoosh.Adapters.Resend`, for two things the emails
  need:

    * custom headers as the object Resend documents
      (`{"List-Unsubscribe": "<…>"}`), so the one-click unsubscribe of
      alerts and digests reaches mail clients (Swoosh 1.29 sends a list);
    * Resend's `Idempotency-Key`, from `email.private[:idempotency_key]`:
      an Oban job retried after a timeout cannot send the same email twice
      (Resend keeps keys 24 hours).

  Config: `api_key` (required), `base_url` (tests).
  """
  use Swoosh.Adapter, required_config: [:api_key]

  alias Swoosh.Email

  @base_url "https://api.resend.com"

  @impl true
  def deliver(%Email{} = email, config) do
    headers =
      [{"authorization", "Bearer " <> config[:api_key]}] ++
        case email.private[:idempotency_key] do
          nil -> []
          key -> [{"idempotency-key", to_string(key)}]
        end

    request =
      Req.new(
        base_url: config[:base_url] || @base_url,
        url: "/emails",
        method: :post,
        headers: headers,
        json: body(email),
        retry: :transient,
        max_retries: 2,
        receive_timeout: 15_000
      )

    case Req.request(request) do
      {:ok, %Req.Response{status: status, body: %{"id" => id}}} when status in 200..299 ->
        {:ok, %{id: id}}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  @doc false
  def body(%Email{} = email) do
    %{
      "from" => address(email.from),
      "to" => Enum.map(email.to, &address/1),
      "subject" => email.subject,
      "text" => email.text_body,
      "html" => email.html_body
    }
    |> put_list("cc", email.cc)
    |> put_list("bcc", email.bcc)
    |> put_reply_to(email.reply_to)
    |> put_headers(email.headers)
    |> Map.reject(fn {_key, value} -> value in [nil, ""] end)
  end

  defp address({name, email}) when name in [nil, ""], do: email
  defp address({name, email}), do: "#{name} <#{email}>"
  defp address(email) when is_binary(email), do: email

  defp put_list(body, _key, []), do: body
  defp put_list(body, key, list), do: Map.put(body, key, Enum.map(list, &address/1))

  defp put_reply_to(body, nil), do: body
  defp put_reply_to(body, reply_to), do: Map.put(body, "reply_to", address(reply_to))

  defp put_headers(body, headers) when map_size(headers) == 0, do: body
  defp put_headers(body, headers), do: Map.put(body, "headers", headers)
end
