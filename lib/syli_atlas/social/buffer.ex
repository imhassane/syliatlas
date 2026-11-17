defmodule SyliAtlas.Social.Buffer do
  @moduledoc """
  Sends posts to Buffer's queue through its GraphQL API (api.buffer.com,
  personal key in `BUFFER_API_KEY`, as a Bearer token).

  The channels are not configured here: each call looks up, in the account's
  first organization, the connected channel of the network (`twitter` for X,
  `linkedin` for LinkedIn). Connecting or replacing an account in Buffer
  needs no change on our side.

  Posts are added to the queue (`addToQueue`): Buffer publishes them at the
  next slot of its posting schedule. The link is in the text on both networks
  (a LinkedIn first comment needs a paid Buffer plan).
  """
  @behaviour SyliAtlas.Social.Publisher

  @services %{x: "twitter", linkedin: "linkedin"}

  @create """
  mutation CreatePost($input: CreatePostInput!) {
    createPost(input: $input) {
      __typename
      ... on PostActionSuccess { post { id } }
      ... on MutationError { message }
    }
  }
  """

  @impl true
  def channels do
    with {:ok, org} <- organization(),
         {:ok, %{"channels" => list}} <-
           query(
             "query Channels($org: OrganizationId!) { channels(input: {organizationId: $org}) { id name service isDisconnected } }",
             %{"org" => org}
           ) do
      {:ok,
       for c <- list, not c["isDisconnected"] do
         %{id: c["id"], name: c["name"], service: c["service"]}
       end}
    end
  end

  @impl true
  def publish(network, %{text: text} = post) when is_map_key(@services, network) do
    with {:ok, channels} <- channels(),
         {:ok, channel} <- channel(channels, network) do
      input =
        %{
          "channelId" => channel.id,
          "text" => text,
          "mode" => "addToQueue",
          "schedulingType" => "automatic",
          "needsApproval" => false,
          "source" => "syliatlas",
          "assets" => assets(post[:image_url])
        }

      case query(@create, %{"input" => input}) do
        {:ok, %{"createPost" => %{"post" => %{"id" => id}}}} -> {:ok, id}
        {:ok, %{"createPost" => %{"message" => message}}} -> {:error, message}
        {:ok, other} -> {:error, "réponse inattendue de Buffer : #{inspect(other)}"}
        {:error, _} = error -> error
      end
    end
  end

  defp channel(channels, network) do
    case Enum.find(channels, &(&1.service == @services[network])) do
      nil -> {:error, "aucun compte #{label(network)} connecté dans Buffer"}
      channel -> {:ok, channel}
    end
  end

  defp label(:x), do: "X"
  defp label(:linkedin), do: "LinkedIn"

  defp assets(nil), do: []
  defp assets(url), do: [%{"image" => %{"url" => url}}]

  defp organization do
    case query("query { account { organizations { id } } }", %{}) do
      {:ok, %{"account" => %{"organizations" => [%{"id" => id} | _]}}} -> {:ok, id}
      {:ok, _} -> {:error, "aucune organisation dans le compte Buffer"}
      error -> error
    end
  end

  defp query(query, variables) do
    config = Application.get_env(:syli_atlas, SyliAtlas.Social, [])

    request =
      Req.new(
        [
          base_url: config[:base_url] || "https://api.buffer.com",
          method: :post,
          headers: [{"authorization", "Bearer " <> (config[:api_key] || "")}],
          json: %{"query" => query, "variables" => variables},
          retry: :transient,
          max_retries: 2,
          receive_timeout: 20_000
        ] ++ Keyword.get(config, :req_options, [])
      )

    case Req.request(request) do
      {:ok, %{status: 200, body: %{"errors" => [%{"message" => m} | _]}}} ->
        {:error, "Buffer : " <> m}

      {:ok, %{status: 200, body: %{"data" => data}}} when is_map(data) ->
        {:ok, data}

      {:ok, %{status: status}} ->
        {:error, "Buffer a répondu #{status}"}

      {:error, exception} ->
        {:error, "Buffer injoignable : " <> Exception.message(exception)}
    end
  end
end
