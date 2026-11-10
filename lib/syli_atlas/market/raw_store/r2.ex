defmodule SyliAtlas.Market.RawStore.R2 do
  @moduledoc """
  Keeps raw payloads in a Cloudflare R2 bucket, through its S3 API, signed
  with AWS Signature V4 (Req's `aws_sigv4`). Needs `R2_ACCOUNT_ID`,
  `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` and `R2_BUCKET`.
  """
  @behaviour SyliAtlas.Market.RawStore

  defp config, do: Application.fetch_env!(:syli_atlas, __MODULE__)

  defp request(method, key, opts) do
    c = config()

    [
      method: method,
      url: "https://#{c[:account_id]}.r2.cloudflarestorage.com/#{c[:bucket]}/#{key}",
      aws_sigv4: [
        access_key_id: c[:access_key_id],
        secret_access_key: c[:secret_access_key],
        service: :s3,
        region: "auto"
      ],
      retry: :transient,
      receive_timeout: 30_000,
      decode_body: false
    ]
    |> Keyword.merge(opts)
    |> Keyword.merge(Keyword.get(c, :req_options, []))
    |> Req.request()
  end

  @impl true
  def put(key, body, content_type) do
    case request(:put, key, body: body, headers: [{"content-type", content_type}]) do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, exception} -> {:error, Exception.message(exception)}
    end
  end

  @impl true
  def get(key) do
    case request(:get, key, []) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, exception} -> {:error, Exception.message(exception)}
    end
  end
end
