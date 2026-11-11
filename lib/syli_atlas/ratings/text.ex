defmodule SyliAtlas.Ratings.Text do
  @moduledoc "Small text helpers for the ratings watch: RSS items, HTML to plain text."

  @months ~w(jan feb mar apr may jun jul aug sep oct nov dec)

  @doc "The items of an RSS 2.0 feed: `%{title, url, summary, published_at}`."
  def rss_items(xml) when is_binary(xml) do
    ~r{<item\b[^>]*>(.*?)</item>}s
    |> Regex.scan(xml, capture: :all_but_first)
    |> Enum.map(fn [item] ->
      %{
        title: tag(item, "title"),
        url: tag(item, "link"),
        summary: item |> tag("description") |> html_to_text() |> String.slice(0, 1000),
        published_at: item |> tag("pubDate") |> rfc1123()
      }
    end)
    |> Enum.filter(&(&1.title != "" and String.starts_with?(&1.url, "http")))
  end

  def rss_items(_), do: []

  defp tag(item, name) do
    case Regex.run(~r{<#{name}\b[^>]*>(.*?)</#{name}>}s, item, capture: :all_but_first) do
      [value] -> value |> cdata() |> unescape() |> String.trim()
      _ -> ""
    end
  end

  defp cdata(s), do: Regex.replace(~r{<!\[CDATA\[(.*?)\]\]>}s, s, "\\1")

  @doc "Readable text of an HTML page or fragment."
  def html_to_text(html) when is_binary(html) do
    html
    |> then(
      &Regex.replace(~r{<(script|style|noscript|svg|nav|footer|header)\b.*?</\1>}is, &1, " ")
    )
    |> then(&Regex.replace(~r{<br\s*/?>|</p>|</li>|</h\d>}i, &1, "\n"))
    |> then(&Regex.replace(~r{<[^>]+>}, &1, " "))
    |> unescape()
    |> then(&Regex.replace(~r{[ \t\r\f\v ]+}u, &1, " "))
    |> then(&Regex.replace(~r{\s*\n\s*}, &1, "\n"))
    |> String.trim()
  end

  def html_to_text(_), do: ""

  @entities %{
    "amp" => "&",
    "lt" => "<",
    "gt" => ">",
    "quot" => "\"",
    "apos" => "'",
    "nbsp" => " ",
    "rsquo" => "’",
    "lsquo" => "‘",
    "rdquo" => "”",
    "ldquo" => "“",
    "laquo" => "«",
    "raquo" => "»",
    "eacute" => "é",
    "egrave" => "è",
    "agrave" => "à",
    "ccedil" => "ç",
    "ecirc" => "ê",
    "ocirc" => "ô",
    "minus" => "−",
    "ndash" => "–",
    "mdash" => "—",
    "hellip" => "…"
  }

  def unescape(s) do
    Regex.replace(~r/&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);/, s, fn whole, code ->
      case code do
        "#x" <> hex -> codepoint(String.to_integer(hex, 16), whole)
        "#" <> dec -> codepoint(String.to_integer(dec), whole)
        name -> Map.get(@entities, name, whole)
      end
    end)
  end

  defp codepoint(n, whole) do
    <<n::utf8>>
  rescue
    _ -> whole
  end

  @doc "Parses an RSS date (`Tue, 10 Nov 2026 10:56:45 GMT`); nil when unreadable."
  def rfc1123(s) do
    with [d, mon, y, h, mi, sec] <-
           Regex.run(~r/(\d{1,2}) ([A-Za-z]{3})\w* (\d{4}) (\d{2}):(\d{2}):(\d{2})/, s || "",
             capture: :all_but_first
           ),
         m when is_integer(m) <- Enum.find_index(@months, &(&1 == String.downcase(mon))),
         {:ok, date} <- Date.new(String.to_integer(y), m + 1, String.to_integer(d)),
         {:ok, time} <-
           Time.new(String.to_integer(h), String.to_integer(mi), String.to_integer(sec)),
         {:ok, dt} <- DateTime.new(date, time) do
      dt
    else
      _ -> nil
    end
  end

  @doc "Lower case, without accents: for keyword matching."
  def fold(s) do
    s
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
  end

  @doc "Same text once whitespace and quotes are normalised (to check AI excerpts)."
  def squash(s) do
    s
    |> String.replace(~r/[’‘]/u, "'")
    |> String.replace(~r/[“”«»]/u, "\"")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> fold()
  end
end
