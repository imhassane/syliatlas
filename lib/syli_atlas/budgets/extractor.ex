defmodule SyliAtlas.Budgets.Extractor do
  @moduledoc """
  Asks Claude to read one document (a PDF of a gazette or a finance law, or
  a web page) and record the budget laws it contains: year, kind, stage,
  dates, totals in the country's currency, and the page where each figure
  is read.

  The AI only reads the document it is given, never its own knowledge.
  What comes out is a proposal for the admin queue, never a publication.

  Key: Railway variable `ANTHROPIC_API_KEY` (shared with the ratings watch).
  Without it, documents wait in the admin (status `no_key`) and laws are
  typed by hand.
  """
  require Logger

  alias SyliAtlas.Budgets.Law

  @url "https://api.anthropic.com/v1/messages"
  @default_model "claude-sonnet-5-5"
  @max_pdf_bytes 24 * 1024 * 1024
  @max_chars 60_000

  def config do
    Application.get_env(:syli_atlas, __MODULE__, [])
    |> Keyword.put_new_lazy(:api_key, fn ->
      Application.get_env(:syli_atlas, SyliAtlas.Ratings.Extractor, [])[:api_key]
    end)
  end

  def configured?, do: config()[:api_key] not in [nil, ""]
  def model, do: config()[:model] || @default_model

  @law %{
    "type" => "object",
    "properties" => %{
      "fiscal_year" => %{"type" => "integer", "description" => "The budget year, e.g. 2026"},
      "kind" => %{
        "type" => "string",
        "enum" => Law.kinds(),
        "description" =>
          "initial: the year's finance law; amending: a supplementary or rectifying finance law; settlement: the law closing the accounts of a past year (loi de règlement); provisional: provisional twelfths or a temporary budget"
      },
      "sequence" => %{
        "type" => "integer",
        "description" => "Rank of an amending law in its year (1 for the first), else 1"
      },
      "stage" => %{
        "type" => "string",
        "enum" => Law.stages(),
        "description" =>
          "tabled: a bill not voted yet; voted: adopted by the legislature; promulgated: signed by the head of state; published: printed in the official gazette"
      },
      "reference" => %{
        "type" => "string",
        "description" => "The law's number, e.g. L/2026/010/CNT"
      },
      "title" => %{"type" => "string", "description" => "The law's title, as written"},
      "legislature" => %{
        "type" => "string",
        "description" => "The body that voted it, as written"
      },
      "tabled_on" => %{"type" => "string", "description" => "YYYY-MM-DD or empty"},
      "voted_on" => %{"type" => "string", "description" => "YYYY-MM-DD or empty"},
      "promulgated_on" => %{"type" => "string", "description" => "YYYY-MM-DD or empty"},
      "published_on" => %{"type" => "string", "description" => "YYYY-MM-DD or empty"},
      "votes_for" => %{"type" => "integer"},
      "votes_against" => %{"type" => "integer"},
      "revenue" => %{
        "type" => "string",
        "description" =>
          "Total budget revenue (resources) authorised, in units of the currency, digits only (e.g. 3372900000000 for 3 372,9 billion). Empty if not stated."
      },
      "expenditure" => %{
        "type" => "string",
        "description" =>
          "Total budget expenditure (charges) authorised, in units of the currency, digits only. Empty if not stated."
      },
      "currency" => %{"type" => "string", "description" => "ISO 4217 code, e.g. XOF, GNF, MGA"},
      "revenue_page" => %{
        "type" => "string",
        "description" => "Page and article where revenue is read"
      },
      "expenditure_page" => %{
        "type" => "string",
        "description" => "Page and article where expenditure is read"
      },
      "excerpt" => %{
        "type" => "string",
        "description" => "The sentence or table line giving the totals, copied verbatim"
      }
    },
    "required" => ["fiscal_year", "kind", "stage", "currency"]
  }

  @tool %{
    "name" => "record_budget_laws",
    "description" =>
      "Records the state budget laws (finance laws) contained in the document. Use an empty list when there are none.",
    "input_schema" => %{
      "type" => "object",
      "properties" => %{"laws" => %{"type" => "array", "items" => @law}},
      "required" => ["laws"]
    }
  }

  @doc """
  Laws found in a document: `{:ok, [%{fields, evidence}]}` or
  `{:error, reason}`. `country` is `%{code, name, currency}`.
  """
  def extract(body, content_type, country) do
    cond do
      not configured?() -> {:error, :no_api_key}
      pdf?(body, content_type) and byte_size(body) > @max_pdf_bytes -> {:error, :too_large}
      true -> call(content(body, content_type), country)
    end
  end

  defp pdf?(body, content_type),
    do: content_type == "application/pdf" or String.starts_with?(body, "%PDF")

  defp content(body, content_type) do
    if pdf?(body, content_type) do
      [
        %{
          "type" => "document",
          "source" => %{
            "type" => "base64",
            "media_type" => "application/pdf",
            "data" => Base.encode64(body)
          }
        },
        %{"type" => "text", "text" => "Record the budget laws of this document."}
      ]
    else
      text =
        body
        |> to_utf8()
        |> String.replace(~r/<(script|style)[^>]*>.*?<\/\1>/is, " ")
        |> String.replace(~r/<[^>]+>/, " ")
        |> String.replace(~r/\s+/, " ")
        |> String.slice(0, @max_chars)

      [%{"type" => "text", "text" => "Document:\n" <> text}]
    end
  end

  defp to_utf8(body) do
    if String.valid?(body), do: body, else: :unicode.characters_to_binary(body, :latin1)
  end

  defp call(content, country) do
    payload = %{
      "model" => model(),
      "max_tokens" => 3000,
      "system" => """
      You read one official document of #{country.name} (#{country.code}) and record the state budget laws it contains: initial finance laws, amending (rectifying) finance laws, settlement laws, provisional budgets.
      Rules:
      - Use only the document, never your own knowledge. If a figure is not in the document, leave it empty.
      - Amounts are the totals of the state budget authorised by the law, in units of the currency (convert « milliards » or « millions » to digits). The country's currency is #{country.currency || "unknown"}.
      - Give the page (and article) where each total is read, and copy the sentence or table line verbatim in excerpt.
      - Ignore laws that are not budget laws (loan ratifications, codes, appointments).
      - A bill presented but not yet voted is stage « tabled ».
      """,
      "tools" => [@tool],
      "tool_choice" => %{"type" => "tool", "name" => "record_budget_laws"},
      "messages" => [%{"role" => "user", "content" => content}]
    }

    [
      url: @url,
      method: :post,
      json: payload,
      headers: [{"x-api-key", config()[:api_key]}, {"anthropic-version", "2023-06-01"}],
      receive_timeout: 180_000
    ]
    |> Keyword.merge(config()[:req_options] || [])
    |> Req.request()
    |> case do
      {:ok, %Req.Response{status: 200, body: %{"content" => content}}} ->
        case Enum.find(content, &(&1["type"] == "tool_use")) do
          %{"input" => %{"laws" => laws}} when is_list(laws) ->
            {:ok, Enum.map(laws, &normalize/1)}

          _ ->
            {:ok, []}
        end

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("budget extractor: HTTP #{status} #{inspect(body) |> String.slice(0, 300)}")
        {:error, {:http, status}}

      {:error, error} ->
        {:error, error}
    end
  end

  defp normalize(law) do
    fields =
      law
      |> Map.take(
        ~w(fiscal_year kind sequence stage reference title legislature tabled_on voted_on
                     promulgated_on published_on votes_for votes_against revenue expenditure currency)
      )
      |> Map.new(fn
        {k, v} when k in ~w(tabled_on voted_on promulgated_on published_on) ->
          {k, if(is_binary(v) and Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, v), do: v, else: nil)}

        {k, v} when k in ~w(revenue expenditure) ->
          {k, if(is_binary(v), do: String.replace(v, ~r/[^\d.]/, ""), else: v)}

        kv ->
          kv
      end)

    evidence =
      %{
        "revenue" => law["revenue_page"],
        "expenditure" => law["expenditure_page"],
        "excerpt" => law["excerpt"] && String.slice(law["excerpt"], 0, 600)
      }
      |> Map.reject(fn {_, v} -> v in [nil, ""] end)

    %{fields: fields, evidence: evidence}
  end
end
