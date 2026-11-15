defmodule SyliAtlas.National.Verify do
  @moduledoc """
  The automatic checks a national figure must pass to be published without
  a person (decision of 14 Nov. 2026):

    * `official_source`: the document comes from one of the country's
      official domains (statistics institute, central bank, ministry),
      never from a newspaper;
    * `in_document`: the sentence given as the source is found word for
      word in the document, and holds the number (checked by code, not by
      a model);
    * `two_reads`: two independent extractions agree on the value, the
      period, the unit and the currency;
    * `arithmetic`: local currency ÷ rate ≈ amount in dollars (2 %);
    * `gap_vs_imf`: less than 15 % away from the IMF's figure of the year;
    * `known_country`: the country already has a counted figure (the first
      one always goes to a person).

  All passed: `auto_verified`, counted at once. Otherwise
  `pending_review`: shown with the « being checked » badge, kept out of
  totals, rankings and map colours until a person decides.
  """

  @max_gap 0.15
  @max_fx_drift 0.02
  @number_tolerance 0.005

  @type ctx :: %{
          optional(:document) => String.t() | nil,
          optional(:second_read) => map | nil,
          optional(:imf) => number | nil,
          optional(:domains) => [String.t()],
          optional(:known_country?) => boolean
        }

  @doc "Runs every check. Returns `{status, checks}`; checks are stored with the figure."
  @spec run(map, ctx) :: {String.t(), map}
  def run(attrs, ctx) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    value = to_float(attrs["value"])
    gap = gap(value, ctx[:imf])

    checks = %{
      "official_source" => official_source?(attrs["source_url"], ctx[:domains] || []),
      "in_document" => in_document?(attrs["quote"], ctx[:document], value, attrs["value_lcu"]),
      "two_reads" => two_reads?(attrs, ctx[:second_read]),
      "arithmetic" => arithmetic?(attrs),
      "gap_vs_imf" => gap != nil and abs(gap) < @max_gap,
      "known_country" => ctx[:known_country?] == true,
      "gap_pct" => gap && Float.round(gap * 100, 1)
    }

    passed? =
      Enum.all?(
        ~w(official_source in_document two_reads arithmetic gap_vs_imf known_country),
        &(checks[&1] == true)
      )

    {if(passed?, do: "auto_verified", else: "pending_review"), checks}
  end

  @doc "The relative gap with the IMF's figure, or nil when either is missing."
  def gap(value, imf) when is_number(value) and is_number(imf) and imf != 0,
    do: value / imf - 1

  def gap(_value, _imf), do: nil

  @doc "Is the URL on one of the country's official domains (or a subdomain)?"
  def official_source?(url, domains) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host} when is_binary(host) ->
        host = String.downcase(host)
        Enum.any?(domains, &(host == &1 or String.ends_with?(host, "." <> &1)))

      _ ->
        false
    end
  end

  def official_source?(_url, _domains), do: false

  @doc """
  Is the quote in the document, word for word (spaces and case aside), and
  does it hold the figure, in dollars or in local currency, at any scale
  (« 24.03 trillion birr » holds 24 030 000 000 000)?
  """
  def in_document?(quote, document, value, value_lcu)
      when is_binary(quote) and is_binary(document) and quote != "" do
    String.contains?(normalize_text(document), normalize_text(quote)) and
      holds_number?(quote, [value, to_float(value_lcu)])
  end

  def in_document?(_quote, _document, _value, _lcu), do: false

  defp holds_number?(quote, targets) do
    targets = Enum.filter(targets, &is_number/1)

    for token <- numbers(quote),
        scale <- [1, 1.0e3, 1.0e6, 1.0e9, 1.0e12],
        target <- targets,
        reduce: false do
      true -> true
      false -> close?(token * scale, target, @number_tolerance)
    end
  end

  @doc "The numbers written in a text: « 24.03 », « 24,03 », « 1,234.5 », « 201 420 »."
  def numbers(text) do
    ~r/\d[\d\s\x{00A0}\x{202F}]*(?:[.,]\d+)*/u
    |> Regex.scan(text)
    |> Enum.map(fn [n] -> parse_number(n) end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_number(raw) do
    s = String.replace(raw, ~r/[\s\x{00A0}\x{202F}]/u, "")

    s =
      cond do
        # 1,234.5 or 1.234,5: the last separator is the decimal one.
        String.contains?(s, ",") and String.contains?(s, ".") ->
          {last_dot, last_comma} = {last_index(s, "."), last_index(s, ",")}

          if last_dot > last_comma,
            do: String.replace(s, ",", ""),
            else: s |> String.replace(".", "") |> String.replace(",", ".")

        # 24,03 (decimal) or 1,234 (thousands: three digits after).
        String.contains?(s, ",") ->
          if Regex.match?(~r/,\d{3}$/, s) and not Regex.match?(~r/^0,/, s),
            do: String.replace(s, ",", ""),
            else: String.replace(s, ",", ".")

        true ->
          s
      end

    case Float.parse(s) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp last_index(s, char) do
    case :binary.matches(s, char) do
      [] -> -1
      matches -> matches |> List.last() |> elem(0)
    end
  end

  @doc "Do two extractions agree on value, period, unit and currency?"
  def two_reads?(_attrs, nil), do: false

  def two_reads?(a, b) do
    b = Map.new(b, fn {k, v} -> {to_string(k), v} end)

    close?(to_float(a["value"]), to_float(b["value"]), 1.0e-9) and
      a["period_label"] == b["period_label"] and
      a["indicator"] == b["indicator"] and
      (a["currency"] || nil) == (b["currency"] || nil)
  end

  @doc "Local currency ÷ rate ≈ the dollar amount (billions). Not applicable: true."
  def arithmetic?(%{"indicator" => "gdp_usd_bn"} = a) do
    with lcu when is_number(lcu) <- to_float(a["value_lcu"]),
         rate when is_number(rate) and rate > 0 <- to_float(a["fx_rate"]),
         value when is_number(value) <- to_float(a["value"]) do
      close?(lcu / rate / 1.0e9, value, @max_fx_drift)
    else
      _ -> a["value_lcu"] in [nil, ""] or a["fx_rate"] in [nil, ""]
    end
  end

  def arithmetic?(_attrs), do: true

  defp close?(a, b, tolerance) when is_number(a) and is_number(b) do
    cond do
      a == b -> true
      b == 0 -> abs(a) < tolerance
      true -> abs(a / b - 1) <= tolerance
    end
  end

  defp close?(_a, _b, _tolerance), do: false

  defp normalize_text(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[\s\x{00A0}\x{202F}]+/u, " ")
    |> String.replace(~r/[’‘]/u, "'")
    |> String.trim()
  end

  @doc false
  def to_float(nil), do: nil
  def to_float(""), do: nil
  def to_float(n) when is_number(n), do: n * 1.0

  def to_float(s) when is_binary(s) do
    case Float.parse(s) do
      {f, ""} -> f
      _ -> nil
    end
  end
end
