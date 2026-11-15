defmodule SyliAtlas.SearchConsole do
  @moduledoc """
  Google Search Console, imported each day with a service account
  (`SearchConsoleWorker`, 07:00 UTC): clicks, impressions and average
  position by query, page, device and country, kept per day in
  `search_console_rows`, read by `/admin/recherche-google` and
  `/admin/traductions`.

  Set-up, once: a service account in a Google Cloud project with the
  Search Console API enabled, its e-mail added as a user (read) of the
  property, its JSON key in `GOOGLE_SEARCH_CONSOLE_KEY` (the JSON itself, or
  base64) and the property in `GOOGLE_SEARCH_CONSOLE_SITE` (`sc-domain:
  syliatlas.com` or `https://syliatlas.com/`). Without them, nothing runs.

  Google's figures arrive about two days late: each run reads the last
  available days again (they keep changing for a while) and replaces them.
  """
  import Ecto.Query
  require Logger
  alias SyliAtlas.Repo

  @dimensions ~w(query page device country)
  @scope "https://www.googleapis.com/auth/webmasters.readonly"
  @token_url "https://oauth2.googleapis.com/token"
  @api "https://searchconsole.googleapis.com/webmasters/v3/sites/"
  @row_limit 5000

  def config, do: Application.get_env(:syli_atlas, __MODULE__, [])
  def dimensions, do: @dimensions

  @doc "Is a key and a property set?"
  def configured?, do: key() != nil and is_binary(config()[:site])

  @doc "The site's property, as set."
  def site, do: config()[:site]

  # ---------------------------------------------------------------------------
  # Import

  @doc """
  Imports `days` (dates) for every dimension, replacing what was stored for
  them. `{:ok, rows}` or `{:error, reason}`.
  """
  def import_days(days) when is_list(days) do
    with {:ok, token} <- token() do
      Enum.reduce_while(days, {:ok, 0}, fn day, {:ok, n} ->
        case import_day(token, day) do
          {:ok, m} -> {:cont, {:ok, n + m}}
          error -> {:halt, error}
        end
      end)
    end
  end

  defp import_day(token, day) do
    results =
      for dim <- @dimensions do
        {dim, query(token, day, dim)}
      end

    case Enum.find(results, &match?({_, {:error, _}}, &1)) do
      {_, error} ->
        error

      nil ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        rows =
          for {dim, {:ok, list}} <- results, r <- list do
            %{
              date: day,
              dimension: dim,
              key: r.key,
              clicks: r.clicks,
              impressions: r.impressions,
              position: r.position,
              inserted_at: now
            }
          end

        Repo.transaction(fn ->
          Repo.delete_all(from r in "search_console_rows", where: r.date == ^day)

          rows
          |> Enum.chunk_every(500)
          |> Enum.each(&Repo.insert_all("search_console_rows", &1))
        end)

        {:ok, length(rows)}
    end
  end

  defp query(token, day, dim) do
    body = %{
      "startDate" => Date.to_iso8601(day),
      "endDate" => Date.to_iso8601(day),
      "dimensions" => [dim],
      "rowLimit" => @row_limit,
      "dataState" => "all"
    }

    url = @api <> URI.encode_www_form(site()) <> "/searchAnalytics/query"

    case Req.post(req(), url: url, json: body, auth: {:bearer, token}) do
      {:ok, %{status: 200, body: %{} = b}} ->
        {:ok,
         for r <- b["rows"] || [], [k | _] = r["keys"] do
           %{
             key: String.slice(k, 0, 500),
             clicks: round(r["clicks"] || 0),
             impressions: round(r["impressions"] || 0),
             position: r["position"]
           }
         end}

      {:ok, %{status: status, body: b}} ->
        {:error, {:http, status, error_message(b)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp error_message(%{"error" => %{"message" => m}}), do: m
  defp error_message(_), do: nil

  # ---------------------------------------------------------------------------
  # Service account: a JWT signed with the account's key, exchanged for an
  # access token (one hour).

  @doc false
  def token do
    with %{"client_email" => email, "private_key" => pem} <- key() || {:error, :not_configured},
         {:ok, assertion} <- assertion(email, pem) do
      form = [grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: assertion]

      case Req.post(req(), url: @token_url, form: form) do
        {:ok, %{status: 200, body: %{"access_token" => t}}} ->
          {:ok, t}

        {:ok, %{status: s, body: b}} ->
          {:error, {:token, s, b["error_description"] || b["error"]}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc false
  def assertion(email, pem) do
    now = System.os_time(:second)
    header = %{"alg" => "RS256", "typ" => "JWT"}

    claims = %{
      "iss" => email,
      "scope" => @scope,
      "aud" => @token_url,
      "iat" => now,
      "exp" => now + 3600
    }

    signing_input = b64(Jason.encode!(header)) <> "." <> b64(Jason.encode!(claims))

    with [entry | _] <- :public_key.pem_decode(pem),
         key <- :public_key.pem_entry_decode(entry) do
      signature = :public_key.sign(signing_input, :sha256, key)
      {:ok, signing_input <> "." <> b64(signature)}
    else
      _ -> {:error, :bad_key}
    end
  rescue
    _ -> {:error, :bad_key}
  end

  defp b64(data), do: Base.url_encode64(data, padding: false)

  # The JSON key, as set (raw JSON or base64).
  defp key do
    case config()[:key] do
      nil ->
        nil

      "" ->
        nil

      text ->
        decoded =
          if String.starts_with?(String.trim_leading(text), "{"),
            do: text,
            else: Base.decode64!(text, ignore: :whitespace)

        Jason.decode!(decoded)
    end
  rescue
    _ -> nil
  end

  defp req do
    Req.new(receive_timeout: 30_000, retry: :transient)
    |> Req.merge(config()[:req_options] || [])
  end

  # ---------------------------------------------------------------------------
  # Reading

  @doc "The last day stored, or nil."
  def last_day, do: Repo.one(from r in "search_console_rows", select: type(max(r.date), :date))

  @doc "Totals over the `days` last days stored: `%{clicks, impressions, position, from, to}`."
  def totals(days \\ 28) do
    case window(days) do
      nil ->
        nil

      {from, to} ->
        {clicks, impressions, weighted} =
          Repo.one(
            from r in "search_console_rows",
              where: r.dimension == "device" and r.date >= ^from and r.date <= ^to,
              select:
                {coalesce(sum(r.clicks), 0), coalesce(sum(r.impressions), 0),
                 sum(r.position * r.impressions)}
          )

        %{
          clicks: clicks,
          impressions: impressions,
          position: if(impressions > 0 and weighted, do: weighted / impressions),
          from: from,
          to: to
        }
    end
  end

  @doc "Impressions and clicks per day, oldest first."
  def daily(days \\ 28) do
    case window(days) do
      nil ->
        []

      {from, to} ->
        Repo.all(
          from r in "search_console_rows",
            where: r.dimension == "device" and r.date >= ^from and r.date <= ^to,
            group_by: r.date,
            order_by: r.date,
            select: %{
              date: type(r.date, :date),
              clicks: sum(r.clicks),
              impressions: sum(r.impressions)
            }
        )
    end
  end

  @doc "Rows of a dimension over the period, summed, most impressions first."
  def top(dimension, days \\ 28, limit \\ 50) when dimension in @dimensions do
    case window(days) do
      nil ->
        []

      {from, to} ->
        Repo.all(
          from r in "search_console_rows",
            where: r.dimension == ^dimension and r.date >= ^from and r.date <= ^to,
            group_by: r.key,
            order_by: [desc: sum(r.impressions), asc: r.key],
            limit: ^limit,
            select: %{
              key: r.key,
              clicks: sum(r.clicks),
              impressions: sum(r.impressions),
              position:
                fragment("sum(? * ?) / max(sum(?), 1)", r.position, r.impressions, r.impressions)
            }
        )
    end
  end

  @doc "Queries on the first page (position ≤ 12) without a click: what to work on."
  def opportunities(days \\ 28, limit \\ 30) do
    "query"
    |> top(days, 2000)
    |> Enum.filter(&(&1.clicks == 0 and is_number(&1.position) and &1.position <= 12))
    |> Enum.take(limit)
  end

  @doc "Pages grouped by language and by section of the address (`/pt/bolsas/…` → pt, bolsas)."
  def by_section(days \\ 28) do
    "page"
    |> top(days, 10_000)
    |> Enum.group_by(fn r -> section(r.key) end)
    |> Enum.map(fn {{lang, sec}, rows} ->
      impressions = rows |> Enum.map(& &1.impressions) |> Enum.sum()

      weighted =
        rows |> Enum.map(&((&1.position || 0) * &1.impressions)) |> Enum.sum()

      %{
        lang: lang,
        section: sec,
        pages: length(rows),
        clicks: rows |> Enum.map(& &1.clicks) |> Enum.sum(),
        impressions: impressions,
        position: if(impressions > 0, do: weighted / impressions)
      }
    end)
    |> Enum.sort_by(&(-&1.impressions))
  end

  @doc "The language and first section of a page address."
  def section(url) do
    path = URI.parse(url).path || "/"

    case String.split(path, "/", trim: true) do
      [lang, sec | _] -> {lang, sec}
      [lang] -> {lang, ""}
      [] -> {"", ""}
    end
  end

  defp window(days) do
    case last_day() do
      nil -> nil
      %Date{} = to -> {Date.add(to, -(days - 1)), to}
    end
  end

  # ---------------------------------------------------------------------------
  # Translation reviews

  @doc "Reviews by path: `%{path => %{reviewer, reviewed_at}}`."
  def reviews do
    Repo.all(
      from r in "translation_reviews",
        select: {r.path, r.reviewer, type(r.reviewed_at, :utc_datetime)}
    )
    |> Map.new(fn {p, who, at} -> {p, %{reviewer: who, reviewed_at: at}} end)
  end

  @doc "Records that a native speaker read a page."
  def review!(path, reviewer) when is_binary(path) and is_binary(reviewer) do
    Repo.insert_all(
      "translation_reviews",
      [
        %{
          path: path,
          reviewer: String.slice(String.trim(reviewer), 0, 80),
          reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }
      ],
      on_conflict: {:replace, [:reviewer, :reviewed_at]},
      conflict_target: [:path]
    )

    :ok
  end

  @doc "Pages of languages other than French and English, most seen first."
  def pages_to_review(days \\ 28) do
    reviews = reviews()

    for r <- top("page", days, 10_000),
        path = URI.parse(r.key).path || "",
        {lang, _} = section(r.key),
        lang in ~w(es pt ar hi zh) do
      Map.merge(r, %{path: path, lang: lang, review: reviews[path]})
    end
  end
end
