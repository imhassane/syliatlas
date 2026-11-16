defmodule SyliAtlas.Companies.Verifier do
  @moduledoc """
  Checks one company against its source page, with Claude, under strict
  rules. The AI only reads the page it is given; the code decides:

  - the page must be reachable and be a web page (not a PDF or a file);
  - the AI must answer « confirmed » and copy a sentence of the page word
    for word; the code finds that sentence in the page, or rejects;
  - the sentence must name the company and the product;
  - the page must name the country, and every owner shown on the site;
  - anything else (a doubt, a contradiction, a page that changed, an
    error) is a refusal, with its reason.

  `check/1` returns `{:confirmed, excerpt}`, `{:rejected, reason}` (in
  French, like the administration where it is read) or
  `{:error, reason}` (no key, the API down: nothing is concluded).

  Key: the Railway variable `ANTHROPIC_API_KEY` (as for the ratings watch);
  `COMPANIES_VERIFY_MODEL` changes the model.
  """
  require Logger

  alias SyliAtlas.Companies.Company
  alias SyliAtlas.Ratings.Text

  @api "https://api.anthropic.com/v1/messages"
  @default_model "claude-haiku-5-5"
  @max_chars 60_000
  @user_agent "SyliAtlasBot/1.0 (+https://syliatlas.com/fr/a-propos)"

  def config, do: Application.get_env(:syli_atlas, __MODULE__, [])

  defp api_key,
    do:
      config()[:api_key] ||
        Application.get_env(:syli_atlas, SyliAtlas.Ratings.Extractor, [])[:api_key]

  def configured?, do: api_key() not in [nil, ""]

  # Words that name each product in the sources (English, French,
  # Portuguese, Spanish), folded (no accents, lower case).
  @keywords %{
    "cocoa" => ~w(cocoa cacao cacau),
    "coffee" => ~w(coffee cafe),
    "tea" => ~w(tea),
    "cashew" => ~w(cashew cajou caju),
    "cotton" => ~w(cotton coton algodao algodon),
    "rubber" => ~w(rubber caoutchouc hevea),
    "vanilla" => ~w(vanilla vanille),
    "flowers" => ~w(flower flowers fleurs roses),
    "crude-oil" => ~w(oil petrole petroleo crude),
    "gas" => ~w(gas gaz lng),
    "gold" => ~w(gold aurifere ouro),
    "diamonds" => ~w(diamond diamonds diamant diamants diamantes),
    "platinum" => ~w(platinum pgm pgms platine),
    "copper" => ~w(copper cuivre cobre),
    "cobalt" => ~w(cobalt cobalto),
    "iron-ore" => ~w(iron fer ferro),
    "manganese" => ~w(manganese manganes),
    "phosphates" => ~w(phosphate phosphates fosfato fosfatos),
    "uranium" => ~w(uranium uranio),
    "wheat" => ~w(wheat ble trigo),
    "rice" => ~w(rice riz arroz),
    "sugar" => ~w(sugar sucre acucar azucar),
    "palm-oil" => ~w(palm palme palma),
    "cars" => ~w(vehicle vehicles cars automobile automobiles)
  }

  # Other names of a country in the sources.
  @aliases %{
    "COD" => ["DRC", "Congo", "RDC", "Democratic Republic of the Congo"],
    "COG" => ["Republic of Congo", "Congo-Brazzaville"],
    "CIV" => ["Ivory Coast", "Côte d'Ivoire", "Cote d'Ivoire"],
    "ZAF" => ["South Africa", "Afrique du Sud"],
    "ZMB" => ["Zambia", "Zambie"],
    "MAR" => ["Morocco", "Maroc"]
  }

  # Words of a company name that do not identify it.
  @generic ~w(company companies mining mines mine group holdings holding plc ltd limited
              societe investments resources minerals copper gold the and des)

  @tool %{
    "name" => "record_verdict",
    "description" => "Records whether the page confirms the facts given about the company.",
    "input_schema" => %{
      "type" => "object",
      "properties" => %{
        "verdict" => %{
          "type" => "string",
          "enum" => ["confirmed", "contradicted", "not_found"],
          "description" =>
            "confirmed only if the page itself states that this company (or mine) produces or handles this product in this country"
        },
        "excerpt" => %{
          "type" => "string",
          "description" =>
            "One sentence of the page, copied word for word, that names the company and the product. Empty if there is none."
        },
        "owners_confirmed" => %{
          "type" => "boolean",
          "description" =>
            "true only if the page names every listed owner as an owner, shareholder or partner of the company. true when no owner is listed."
        },
        "reason" => %{
          "type" => "string",
          "description" => "One short sentence in French: why."
        }
      },
      "required" => ["verdict", "excerpt", "owners_confirmed", "reason"]
    }
  }

  @doc "Checks a company against its source page."
  def check(%Company{} = c) do
    cond do
      not configured?() ->
        {:error, :no_api_key}

      true ->
        with {:ok, text} <- fetch(c.source_url),
             {:ok, verdict} <- ask(c, text) do
          judge(c, text, verdict)
        end
    end
  end

  @doc "The page as text, or `{:rejected, reason}` when it cannot be read as a web page."
  def fetch(url) do
    [
      url: url,
      headers: [{"user-agent", @user_agent}, {"accept", "text/html,application/xhtml+xml"}],
      receive_timeout: 30_000,
      max_redirects: 5,
      retry: false,
      decode_body: false
    ]
    |> Keyword.merge(config()[:req_options] || [])
    |> Req.get()
    |> case do
      {:ok, %Req.Response{status: 200} = resp} ->
        type = resp |> Req.Response.get_header("content-type") |> List.first() |> to_string()

        if String.contains?(type, "html") or type == "" do
          text = resp.body |> to_string() |> Text.html_to_text()

          if String.length(text) < 200,
            do: {:rejected, "page vide ou bloquée"},
            else: {:ok, String.slice(text, 0, @max_chars)}
        else
          {:rejected, "pas une page web (#{type})"}
        end

      {:ok, %Req.Response{status: status}} ->
        {:rejected, "la source a répondu HTTP #{status}"}

      {:error, error} ->
        {:rejected, "source injoignable (#{Exception.message(error) |> String.slice(0, 80)})"}
    end
  end

  defp ask(c, text) do
    payload = %{
      "model" => config()[:model] || @default_model,
      "max_tokens" => 600,
      "system" => """
      You check one fact about a company against one web page. Use only the page, never your own knowledge.
      Answer "confirmed" only if the page itself clearly states that the company (or mine) produces, mines or handles the product in the country.
      Answer "contradicted" if the page says the company stopped, was sold, closed, or does not do this.
      Answer "not_found" in every other case, including when you are unsure.
      The excerpt must be copied word for word from the page, without changing a single character.
      """,
      "tools" => [@tool],
      "tool_choice" => %{"type" => "tool", "name" => "record_verdict"},
      "messages" => [
        %{
          "role" => "user",
          "content" => """
          Company or mine: #{c.name}
          Product: #{product_words(c.product)}
          Country: #{country_name(c.country)}
          Owners listed: #{if c.owners in [nil, ""], do: "(none)", else: c.owners}

          Page (#{c.source_url}):
          #{text}
          """
        }
      ]
    }

    [
      url: @api,
      method: :post,
      json: payload,
      headers: [{"x-api-key", api_key()}, {"anthropic-version", "2023-06-01"}],
      receive_timeout: 90_000
    ]
    |> Keyword.merge(config()[:api_req_options] || [])
    |> Req.request()
    |> case do
      {:ok, %Req.Response{status: 200, body: %{"content" => content}}} ->
        case Enum.find(content, &(&1["type"] == "tool_use")) do
          %{"input" => input} when is_map(input) -> {:ok, input}
          _ -> {:rejected, "pas de verdict de l'IA"}
        end

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error(
          "companies verifier: HTTP #{status} #{inspect(body) |> String.slice(0, 300)}"
        )

        {:error, {:http, status}}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc false
  def judge(c, text, v) do
    excerpt = to_string(v["excerpt"])
    page = Text.squash(text)
    quote = Text.squash(excerpt)

    cond do
      v["verdict"] == "contradicted" ->
        {:rejected, "la source le contredit : " <> to_string(v["reason"])}

      v["verdict"] != "confirmed" ->
        {:rejected, "non confirmé par la source : " <> to_string(v["reason"])}

      String.length(excerpt) < 30 ->
        {:rejected, "extrait trop court"}

      not String.contains?(page, quote) ->
        {:rejected, "extrait introuvable mot pour mot dans la page"}

      not names_company?(quote, c.name) ->
        {:rejected, "l'extrait ne nomme pas l'entreprise"}

      not Enum.any?(keywords(c.product), &word?(quote, &1)) ->
        {:rejected, "l'extrait ne nomme pas le produit"}

      not names_country?(page, c.country) ->
        {:rejected, "la page ne nomme pas le pays"}

      c.owners not in [nil, ""] and v["owners_confirmed"] != true ->
        {:rejected, "actionnaires non confirmés par la source"}

      c.owners not in [nil, ""] and not owners_named?(page, c.owners) ->
        {:rejected, "un actionnaire n'est pas nommé dans la page"}

      true ->
        {:confirmed, String.slice(String.trim(excerpt), 0, 600)}
    end
  end

  defp keywords(product), do: Map.get(@keywords, product, [product])
  defp product_words(product), do: Enum.join(keywords(product), " / ")

  defp word?(text, word), do: Regex.match?(~r/\b#{Regex.escape(word)}\b/u, text)

  defp tokens(name) do
    name
    |> Text.fold()
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> Enum.reject(&(String.length(&1) < 3 or &1 in @generic))
  end

  defp names_company?(quote, name) do
    case tokens(name) do
      [] -> String.contains?(quote, Text.fold(name))
      words -> Enum.any?(words, &word?(quote, &1))
    end
  end

  defp names_country?(page, code) do
    area = SyliAtlas.Geo.get_area_by_code(code)
    names = Map.get(@aliases, code, []) ++ if(area, do: [area.name_en, area.name_fr], else: [])
    Enum.any?(names, &String.contains?(page, Text.squash(&1)))
  end

  defp owners_named?(page, owners) do
    owners
    |> String.split(~r/\s*[,;]\s*/, trim: true)
    |> Enum.all?(fn owner ->
      case tokens(owner) do
        [] -> String.contains?(page, Text.squash(owner))
        [first | _] -> word?(page, first)
      end
    end)
  end

  defp country_name(code) do
    case SyliAtlas.Geo.get_area_by_code(code) do
      nil -> code
      area -> area.name_en
    end
  end
end
