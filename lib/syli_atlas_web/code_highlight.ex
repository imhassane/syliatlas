defmodule SyliAtlasWeb.CodeHighlight do
  @moduledoc """
  Colours code examples on the server, for the API page: JSON, CSV, shell
  (curl, spreadsheet formulas) and short JavaScript or Python. Returns lines
  of `{class, text}` tokens; the page wraps each in a `<span class="tok-…">`.
  No JavaScript in the browser, nothing to load.

  Classes: `key`, `str`, `num`, `kw`, `punc`, `com`, `cmd`, `url`, `flag`,
  `fn`, `plain`.
  """

  @type token :: {String.t(), String.t()}

  @json ~r/("(?:[^"\\]|\\.)*")(\s*:)?|(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)|\b(true|false|null)\b|([{}\[\],:])|(\s+)|([^\s"{}\[\],:]+)|(.)/u
  @shell ~r/(^\$)|(curl|=IMPORTDATA)|("?https?:\/\/[^\s"]+"?)|(\s-[A-Za-z]+)|(\s+)|([()])|([^\s"()]+)|(.)/u
  @code ~r/(\/\/.*$|#.*$)|("(?:[^"\\]|\\.)*")|\b(const|let|await|import|as|from|async|return|print)\b|(\b\d+(?:\.\d+)?\b)|([A-Za-z_]\w*)(?=\()|(\s+)|([{}\[\]().,;:=>])|([A-Za-z_]\w*)|(.)/u

  @doc "The lines of `text`, each a list of `{class, text}`."
  @spec lines(String.t(), :json | :csv | :shell | :code) :: [[token]]
  def lines(text, lang) do
    {lines, _} =
      text
      |> String.split("\n")
      |> Enum.map_reduce(true, fn line, header? ->
        cond do
          lang in [:csv, :shell] and String.starts_with?(String.trim_leading(line), "#") ->
            {[{"com", line}], header?}

          lang == :csv ->
            {csv(line, header?), false}

          true ->
            {tokens(line, lang), header?}
        end
      end)

    Enum.map(lines, fn
      [] -> [{"plain", " "}]
      tokens -> tokens
    end)
  end

  defp csv(line, header?) do
    ~r/[^,]+|,/u
    |> Regex.scan(line)
    |> Enum.map(fn
      [","] -> {"punc", ","}
      [cell] when header? -> {"key", cell}
      ["…"] -> {"punc", "…"}
      [cell] -> {if(number?(cell), do: "num", else: "str"), cell}
    end)
  end

  defp tokens(line, :json) do
    Regex.scan(@json, line, capture: :all)
    |> Enum.flat_map(fn [all | groups] ->
      case pad(groups, 8) do
        [str, colon, _, _, _, _, _, _] when str != "" ->
          [{if(colon != "", do: "key", else: "str"), str}] ++
            if(colon != "", do: [{"punc", colon}], else: [])

        [_, _, num, _, _, _, _, _] when num != "" ->
          [{"num", num}]

        [_, _, _, kw, _, _, _, _] when kw != "" ->
          [{"kw", kw}]

        [_, _, _, _, punc, _, _, _] when punc != "" ->
          [{"punc", punc}]

        [_, _, _, _, _, _, word, _] when word in ["…", "→"] ->
          [{"punc", word}]

        [_, _, _, _, _, _, word, _] when word != "" ->
          [{word_class(word), word}]

        _ ->
          [{"plain", all}]
      end
    end)
  end

  defp tokens(line, :shell) do
    Regex.scan(@shell, line, capture: :all)
    |> Enum.map(fn [all | groups] ->
      case pad(groups, 8) do
        [p, _, _, _, _, _, _, _] when p != "" -> {"com", p}
        [_, c, _, _, _, _, _, _] when c != "" -> {"cmd", c}
        [_, _, u, _, _, _, _, _] when u != "" -> {"url", u}
        [_, _, _, f, _, _, _, _] when f != "" -> {"flag", f}
        [_, _, _, _, _, p, _, _] when p != "" -> {"punc", p}
        _ -> {"plain", all}
      end
    end)
  end

  defp tokens(line, :code) do
    Regex.scan(@code, line, capture: :all)
    |> Enum.map(fn [all | groups] ->
      case pad(groups, 9) do
        [c | _] when c != "" -> {"com", c}
        [_, s | _] when s != "" -> {"str", s}
        [_, _, k | _] when k != "" -> {"kw", k}
        [_, _, _, n | _] when n != "" -> {"num", n}
        [_, _, _, _, f | _] when f != "" -> {"fn", f}
        [_, _, _, _, _, _, p | _] when p != "" -> {"punc", p}
        _ -> {"plain", all}
      end
    end)
  end

  defp word_class("GET"), do: "cmd"
  defp word_class("/" <> _), do: "url"
  defp word_class(_), do: "plain"

  defp number?(text), do: Regex.match?(~r/^-?\d+(\.\d+)?$/, text)

  # Regex.scan drops trailing empty groups: pad to a fixed width.
  defp pad(groups, n), do: groups ++ List.duplicate("", max(n - length(groups), 0))
end
