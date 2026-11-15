defmodule SyliAtlas.National.RebasingExtractor do
  @moduledoc """
  Asks Claude to read one news article and list the rebasings of national
  accounts it reports (an African country changing the base year of its
  GDP), each with the verbatim sentence it relies on.

  As for ratings (`SyliAtlas.Ratings.Extractor`, same key): the AI only
  reads the text it is given, the code drops any rebasing whose excerpt is
  not in that text word for word, and what comes out is a proposal for the
  admin, never a publication.
  """
  require Logger

  alias SyliAtlas.Ratings.Text

  @url "https://api.anthropic.com/v1/messages"
  @default_model "claude-haiku-5-5"
  @max_chars 14_000

  def config, do: Application.get_env(:syli_atlas, __MODULE__, [])

  defp api_key,
    do:
      config()[:api_key] ||
        Application.get_env(:syli_atlas, SyliAtlas.Ratings.Extractor, [])[:api_key]

  def configured?, do: api_key() not in [nil, ""]

  @tool %{
    "name" => "record_rebasings",
    "description" =>
      "Records the rebasings of national accounts reported in the article. Use an empty list when there are none.",
    "input_schema" => %{
      "type" => "object",
      "properties" => %{
        "rebasings" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "country_code" => %{"type" => "string", "description" => "ISO 3166-1 alpha-3 code"},
              "announced_on" => %{
                "type" => "string",
                "description" =>
                  "YYYY-MM-DD of the announcement if stated or clearly implied, else empty"
              },
              "old_base" => %{
                "type" => "string",
                "description" => "The former base year as written (2015, 2015/16), else empty"
              },
              "new_base" => %{"type" => "string", "description" => "The new base year as written"},
              "level_change_pct" => %{
                "type" => ["number", "null"],
                "description" =>
                  "The revision of the GDP level in percent (59.2 for +59.2 %), null if not stated"
              },
              "institution" => %{
                "type" => "string",
                "description" => "Who published the new accounts (statistics office, ministry)"
              },
              "is_new" => %{
                "type" => "boolean",
                "description" =>
                  "true only if the article reports the rebasing as news (just announced or published), false if it is background or a plan"
              },
              "excerpt" => %{
                "type" => "string",
                "description" =>
                  "The sentence of the article stating the rebasing, copied verbatim"
              }
            },
            "required" => ["country_code", "new_base", "is_new", "excerpt"]
          }
        }
      },
      "required" => ["rebasings"]
    }
  }

  @doc """
  Rebasings found in `text` (title and body of one article), checked:
  `{:ok, [map]}` or `{:error, reason}`. `countries` is `%{code => name}`.
  """
  def extract(title, text, countries) do
    if configured?() do
      body = String.slice(text, 0, @max_chars)

      with {:ok, found} <- call(title, body, countries) do
        {:ok, Enum.flat_map(found, &check(&1, title <> "\n" <> body, countries))}
      end
    else
      {:error, :no_api_key}
    end
  end

  defp call(title, body, countries) do
    list = Enum.map_join(countries, ", ", fn {code, name} -> "#{code} #{name}" end)

    payload = %{
      "model" => config()[:model] || @default_model,
      "max_tokens" => 1200,
      "system" => """
      You read one news article and record the rebasings of national accounts it reports for African countries: a country changing the base (reference) year of its GDP, usually revising the GDP level.
      Rules:
      - Only a rebasing published or officially announced (results released). Ignore plans, projects, workshops, forecasts and rebasings recalled as background.
      - Ignore revisions of growth rates or quarterly figures without a change of base year.
      - Use only the article's text, never your own knowledge. Leave a field empty (or null) when the article does not state it.
      - The excerpt must be copied word for word from the article.
      - Countries (code name): #{list}.
      """,
      "tools" => [@tool],
      "tool_choice" => %{"type" => "tool", "name" => "record_rebasings"},
      "messages" => [%{"role" => "user", "content" => "Title: #{title}\n\nArticle:\n#{body}"}]
    }

    [
      url: @url,
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
          %{"input" => %{"rebasings" => list}} when is_list(list) -> {:ok, list}
          _ -> {:ok, []}
        end

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error(
          "rebasing extractor: HTTP #{status} #{inspect(body) |> String.slice(0, 300)}"
        )

        {:error, {:http, status}}

      {:error, error} ->
        {:error, error}
    end
  end

  # Keeps a rebasing only if it can be checked against the text.
  @doc false
  def check(r, text, countries) do
    excerpt = r["excerpt"] || ""
    new_base = String.trim(r["new_base"] || "")
    change = r["level_change_pct"]

    cond do
      r["is_new"] != true -> []
      not Map.has_key?(countries, r["country_code"]) -> []
      not Regex.match?(~r/(19|20)\d\d/, new_base) -> []
      String.length(excerpt) < 20 -> []
      not String.contains?(Text.squash(text), Text.squash(excerpt)) -> []
      is_number(change) and (change < -50 or change > 300) -> []
      true -> [clean(r, new_base, change)]
    end
  end

  defp clean(r, new_base, change) do
    %{
      "country_code" => r["country_code"],
      "announced_on" =>
        if(Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, r["announced_on"] || ""), do: r["announced_on"]),
      "old_base" => blank(r["old_base"]),
      "new_base" => new_base,
      "level_change_pct" =>
        if(is_number(change), do: :erlang.float_to_binary(change * 1.0, decimals: 1)),
      "institution" => blank(r["institution"]),
      "excerpt" => String.slice(r["excerpt"], 0, 600)
    }
  end

  defp blank(nil), do: nil

  defp blank(s) do
    case String.trim(s) do
      "" -> nil
      t -> t
    end
  end
end
