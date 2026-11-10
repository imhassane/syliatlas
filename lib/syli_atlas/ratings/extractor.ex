defmodule SyliAtlas.Ratings.Extractor do
  @moduledoc """
  Asks Claude to read one news article and list the sovereign rating
  decisions it reports, each with the verbatim sentence it relies on.

  The AI never supplies a rating from memory: it only reads the text it is
  given, and the code drops any decision whose excerpt is not found word for
  word in that text. What comes out is a proposal for the admin queue,
  never a publication.

  Key: Railway variable `ANTHROPIC_API_KEY` (config `:api_key`).
  """
  require Logger

  alias SyliAtlas.Ratings.{Rating, Scale, Text}

  @url "https://api.anthropic.com/v1/messages"
  @default_model "claude-haiku-5-5"
  @max_chars 14_000

  def config, do: Application.get_env(:syli_atlas, __MODULE__, [])
  def configured?, do: config()[:api_key] not in [nil, ""]

  @tool %{
    "name" => "record_decisions",
    "description" =>
      "Records the sovereign credit rating decisions reported in the article. Use an empty list when there are none.",
    "input_schema" => %{
      "type" => "object",
      "properties" => %{
        "decisions" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "country_code" => %{"type" => "string", "description" => "ISO 3166-1 alpha-3 code"},
              "agency" => %{"type" => "string", "enum" => ["sp", "moodys", "fitch", "afcra"]},
              "rating" => %{
                "type" => "string",
                "description" => "The agency's symbol, e.g. BB-, B2, CCC+, SD"
              },
              "outlook" => %{
                "type" => "string",
                "enum" => ["positive", "negative", "stable", "developing", "none", "unknown"]
              },
              "action_date" => %{
                "type" => "string",
                "description" => "YYYY-MM-DD if stated or clearly implied, else empty"
              },
              "action_type" => %{
                "type" => "string",
                "enum" => [
                  "upgrade",
                  "downgrade",
                  "affirmed",
                  "outlook_up",
                  "outlook_down",
                  "outlook",
                  "default"
                ]
              },
              "currency" => %{"type" => "string", "enum" => ["foreign", "local", "unknown"]},
              "is_new" => %{
                "type" => "boolean",
                "description" =>
                  "true only if the article reports this decision as news, false if it is background"
              },
              "excerpt" => %{
                "type" => "string",
                "description" =>
                  "The sentence of the article stating the decision, copied verbatim"
              }
            },
            "required" => [
              "country_code",
              "agency",
              "rating",
              "action_type",
              "currency",
              "is_new",
              "excerpt"
            ]
          }
        }
      },
      "required" => ["decisions"]
    }
  }

  @doc """
  Decisions found in `text` (title and body of one article), checked:
  `{:ok, [map]}` or `{:error, reason}`. `countries` is `%{code => name}`.
  """
  def extract(title, text, countries) do
    if configured?() do
      body = String.slice(text, 0, @max_chars)

      with {:ok, decisions} <- call(title, body, countries) do
        {:ok, Enum.flat_map(decisions, &check(&1, title <> "\n" <> body, countries))}
      end
    else
      {:error, :no_api_key}
    end
  end

  defp call(title, body, countries) do
    list = Enum.map_join(countries, ", ", fn {code, name} -> "#{code} #{name}" end)

    payload = %{
      "model" => config()[:model] || @default_model,
      "max_tokens" => 1500,
      "system" => """
      You read one news article and record the sovereign credit rating decisions it reports for African countries.
      Rules:
      - Only decisions by S&P Global Ratings (sp), Moody's (moodys), Fitch (fitch) or the African Credit Rating Agency AfCRA (afcra) on a country's government (sovereign) long-term rating.
      - Ignore ratings of banks, companies, cities or bonds, short-term ratings, forecasts, analysts' opinions and rumours.
      - Use only the article's text, never your own knowledge. If the article does not give the rating symbol, skip the decision.
      - The excerpt must be copied word for word from the article.
      - Mark is_new false when the article only recalls an older decision as background.
      - Countries (code name): #{list}.
      """,
      "tools" => [@tool],
      "tool_choice" => %{"type" => "tool", "name" => "record_decisions"},
      "messages" => [
        %{"role" => "user", "content" => "Title: #{title}\n\nArticle:\n#{body}"}
      ]
    }

    [
      url: @url,
      method: :post,
      json: payload,
      headers: [
        {"x-api-key", config()[:api_key]},
        {"anthropic-version", "2023-06-01"}
      ],
      receive_timeout: 60_000
    ]
    |> Keyword.merge(config()[:req_options] || [])
    |> Req.request()
    |> case do
      {:ok, %Req.Response{status: 200, body: %{"content" => content}}} ->
        case Enum.find(content, &(&1["type"] == "tool_use")) do
          %{"input" => %{"decisions" => decisions}} when is_list(decisions) -> {:ok, decisions}
          _ -> {:ok, []}
        end

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("ratings extractor: HTTP #{status} #{inspect(body) |> String.slice(0, 300)}")
        {:error, {:http, status}}

      {:error, error} ->
        {:error, error}
    end
  end

  # Keeps a decision only if it can be checked against the text and the scale.
  defp check(d, text, countries) do
    excerpt = d["excerpt"] || ""
    rating = Scale.normalize(d["rating"] || "")

    cond do
      d["is_new"] != true -> []
      d["currency"] == "local" -> []
      not Map.has_key?(countries, d["country_code"]) -> []
      d["agency"] not in Rating.agencies() -> []
      is_nil(Scale.score(rating)) -> []
      String.length(excerpt) < 20 -> []
      not String.contains?(Text.squash(text), Text.squash(excerpt)) -> []
      true -> [%{d | "rating" => rating} |> normalize_fields()]
    end
  end

  defp normalize_fields(d) do
    %{
      "country_code" => d["country_code"],
      "agency" => d["agency"],
      "rating" => d["rating"],
      "outlook" =>
        if(d["outlook"] in ["positive", "negative", "stable", "developing", "none"],
          do: d["outlook"]
        ),
      "action_date" =>
        if(Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, d["action_date"] || ""),
          do: d["action_date"],
          else: ""
        ),
      "action_type" => d["action_type"],
      "excerpt" => String.slice(d["excerpt"], 0, 600)
    }
  end
end
