defmodule SyliAtlas.Social.Writer do
  @moduledoc """
  « Proposer un texte »: Claude writes the X post (English) and the LinkedIn
  post (French) of a page of the site, from what the page shows and nothing
  else. A person reads and edits them before anything is sent.

  Same key as the other readings (`ANTHROPIC_API_KEY`); model
  `claude-haiku-5-5` unless `SOCIAL_WRITER_MODEL` says otherwise. Without a
  key, the page's own title and description stay.
  """
  require Logger

  alias SyliAtlas.Social.Post

  @api "https://api.anthropic.com/v1/messages"
  @default_model "claude-haiku-5-5"

  def config, do: Application.get_env(:syli_atlas, __MODULE__, [])

  defp api_key,
    do:
      config()[:api_key] ||
        Application.get_env(:syli_atlas, SyliAtlas.Ratings.Extractor, [])[:api_key]

  def configured?, do: api_key() not in [nil, ""]

  @tool %{
    "name" => "record_posts",
    "description" => "Records the two posts.",
    "input_schema" => %{
      "type" => "object",
      "properties" => %{
        "x" => %{"type" => "string", "description" => "The X post, in English."},
        "linkedin" => %{"type" => "string", "description" => "The LinkedIn post, in French."}
      },
      "required" => ["x", "linkedin"]
    }
  }

  @doc "The two texts for the page, or an error to show."
  def propose(page) do
    if configured?(), do: ask(page), else: {:error, "Pas de clé Anthropic sur ce serveur."}
  end

  defp ask(page) do
    payload = %{
      "model" => config()[:model] || @default_model,
      "max_tokens" => 1000,
      "system" => """
      You write the social media posts of Syli Atlas, a site of verifiable figures on African economies.
      Use only the page given, never your own knowledge. Every figure you quote must appear in the page, with its year and its source when the page names them.
      Never give an opinion on a government, a country or a policy. No superlatives, no emoji, no hashtags, no link (they are added afterwards).
      X, in English: at most #{Post.x_limit() - 60} characters; one fact or one question that makes people open the page, then a short line ending with a colon (the link follows).
      LinkedIn, in French: two or three short paragraphs; the most telling figures of the page; end with a line saying the details are behind the link, ending with « lien ci-dessous. ».
      """,
      "tools" => [@tool],
      "tool_choice" => %{"type" => "tool", "name" => "record_posts"},
      "messages" => [
        %{
          "role" => "user",
          "content" => """
          English page (#{page.path_en}): #{page.title_en}
          #{page.description_en}
          #{page[:text_en]}

          French page (#{page.path_fr}): #{page.title_fr}
          #{page.description_fr}
          #{page[:text_fr]}
          """
        }
      ]
    }

    [
      url: @api,
      method: :post,
      json: payload,
      headers: [{"x-api-key", api_key()}, {"anthropic-version", "2023-06-01"}],
      receive_timeout: 60_000
    ]
    |> Keyword.merge(config()[:req_options] || [])
    |> Req.request()
    |> case do
      {:ok, %Req.Response{status: 200, body: %{"content" => content}}} ->
        case Enum.find(content, &(&1["type"] == "tool_use")) do
          %{"input" => %{"x" => x, "linkedin" => li}} when is_binary(x) and is_binary(li) ->
            {:ok, %{x: String.trim(x), linkedin: String.trim(li)}}

          _ ->
            {:error, "Claude n'a pas proposé de texte."}
        end

      {:ok, %Req.Response{status: status}} ->
        Logger.error("social writer: HTTP #{status}")
        {:error, "Claude a répondu #{status}."}

      {:error, error} ->
        {:error, "Claude injoignable : " <> Exception.message(error)}
    end
  end
end
