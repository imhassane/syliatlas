defmodule SyliAtlas.Social.Pages do
  @moduledoc """
  A post for any public page of the site (« Partager sur les réseaux »).

  The page is given by its address (pasted, or sent by the admin bar of the
  page itself). It is read the way a visitor gets it, but inside the server
  (the endpoint is called directly, nothing goes out): its title, its
  description, its share image and its translations (`hreflang`). X gets the
  English page, LinkedIn the French one, each with its `utm_source`.

  The first texts are the page's own title and description; « Proposer un
  texte » asks Claude for better ones (`SyliAtlas.Social.Writer`).
  """
  alias SyliAtlas.Geo
  alias SyliAtlas.Social.{Hashtags, Post}
  alias SyliAtlasWeb.Seo

  @hosts ~w(syliatlas.com www.syliatlas.com dev.syliatlas.com localhost)

  @doc """
  The site path of what was given (an address of the site or a path), or an
  error to show. Only public pages, in one of the site's languages.
  """
  def normalize(input) when is_binary(input) do
    uri = input |> String.trim() |> URI.parse()

    cond do
      uri.host not in [nil | hosts()] ->
        {:error, "Cette adresse n'est pas une page de Syli Atlas."}

      not is_binary(uri.path) or not String.starts_with?(uri.path, "/") ->
        {:error, "Collez l'adresse d'une page du site (https://syliatlas.com/fr/…)."}

      true ->
        path = uri.path |> String.trim_trailing("/")

        case String.split(path, "/", trim: true) do
          [locale | _] ->
            if locale in SyliAtlas.Locales.all(),
              do: {:ok, path},
              else: {:error, "Seules les pages publiques du site peuvent être partagées."}

          [] ->
            {:error, "Seules les pages publiques du site peuvent être partagées."}
        end
    end
  end

  def normalize(_), do: {:error, "Adresse manquante."}

  defp hosts, do: Enum.uniq([SyliAtlasWeb.Endpoint.host() | @hosts])

  @doc """
  What the page says of itself, in French and in English:
  `%{path_fr, path_en, title_fr, title_en, description_fr, description_en,
  area_code}`. The French or English page may be missing (then the other
  one serves both networks).
  """
  def describe(path) do
    with {:ok, head} <- read(path) do
      alternates = head.alternates
      locale = path |> String.split("/", trim: true) |> hd()

      fr = if locale == "fr", do: {path, head}, else: other(alternates["fr"])
      en = if locale == "en", do: {path, head}, else: other(alternates["en"])
      {fr_path, fr_head} = fr || en || {path, head}
      {en_path, en_head} = en || fr || {path, head}

      {:ok,
       %{
         path_fr: fr_path,
         path_en: en_path,
         title_fr: fr_head.title,
         title_en: en_head.title,
         description_fr: fr_head.description,
         description_en: en_head.description,
         text_fr: fr_head.text,
         text_en: en_head.text,
         area_code: area_code(fr_path) || area_code(en_path)
       }}
    end
  end

  defp other(nil), do: nil

  defp other(url) do
    path = URI.parse(url).path

    case read(path) do
      {:ok, head} -> {path, head}
      _ -> nil
    end
  end

  # A country or region page: its code, for the hashtags.
  defp area_code(path) do
    case String.split(path, "/", trim: true) do
      [locale, segment, slug | _] when segment in ~w(pays countries regions) ->
        case Geo.get_area_by_slug(slug, locale) do
          %{code: code} -> code
          _ -> nil
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  @doc "The page as a visitor gets it: its head, or an error to show."
  def read(path) do
    conn =
      Plug.Test.conn(:get, path)
      |> Map.put(:host, SyliAtlasWeb.Endpoint.host())
      |> Plug.Conn.put_req_header("accept", "text/html")
      |> SyliAtlasWeb.Endpoint.call([])

    case conn.status do
      200 -> {:ok, head(conn.resp_body)}
      s when s in [301, 302, 308] -> follow(conn)
      404 -> {:error, "Cette page n'existe pas sur le site."}
      s -> {:error, "La page a répondu #{s}."}
    end
  rescue
    # The endpoint raises what a visitor gets as an error page (404…).
    e ->
      case Plug.Exception.status(e) do
        404 -> {:error, "Cette page n'existe pas sur le site."}
        500 -> {:error, "Page illisible : " <> Exception.message(e)}
        s -> {:error, "La page a répondu #{s}."}
      end
  end

  defp follow(conn) do
    case Plug.Conn.get_resp_header(conn, "location") do
      [location | _] ->
        case normalize(location) do
          {:ok, path} when path != conn.request_path -> read(path)
          _ -> {:error, "La page redirige ailleurs."}
        end

      _ ->
        {:error, "La page redirige ailleurs."}
    end
  end

  @doc false
  def head(html) when is_binary(html) do
    [head | rest] = String.split(html, "</head>", parts: 2)

    title =
      case Regex.run(~r{<title[^>]*>(.*?)</title>}s, head) do
        [_, t] -> t |> unescape() |> String.trim() |> String.replace_suffix(" · Syli Atlas", "")
        _ -> nil
      end

    description =
      case Regex.run(~r{<meta[^>]*name="description"[^>]*content="([^"]*)"}s, head) do
        [_, d] -> unescape(d)
        _ -> nil
      end

    links =
      Regex.scan(~r{<link[^>]*rel="alternate"[^>]*hreflang="([^"]+)"[^>]*href="([^"]+)"}s, head)

    alternates =
      for [_, lang, href] <- links, lang != "x-default", into: %{}, do: {lang, unescape(href)}

    %{
      text: rest |> List.first("") |> main_text(),
      title: title,
      description: description,
      alternates: alternates
    }
  end

  # The words of the page's main part, for Claude: no menus, no scripts.
  @max_text 6000

  defp main_text(body) do
    main =
      case Regex.run(~r{<main[^>]*>(.*)</main>}s, body) do
        [_, m] -> m
        _ -> body
      end

    main
    |> String.replace(~r{<(script|style|svg|template)[^>]*>.*?</\1>}s, " ")
    |> String.replace(~r{<[^>]+>}, " ")
    |> unescape()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> String.slice(0, @max_text)
  end

  defp unescape(text) do
    text
    |> String.replace("&#39;", "'")
    |> String.replace("&quot;", "\"")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&nbsp;", " ")
    |> String.replace("&amp;", "&")
  end

  @doc """
  The attributes of a draft for the page (`Post.draft_changeset/2`), with
  first texts made of its title and description, and the hashtags.
  `texts` (`%{x:, linkedin:}`) replaces those texts (Claude's proposal).
  """
  def draft(page, texts \\ nil) do
    link_x = link(page.path_en, "x")
    link_li = link(page.path_fr, "linkedin")

    {x, li} =
      case texts do
        %{x: x, linkedin: li} -> {x, li}
        _ -> {first_x(page, link_x), first_linkedin(page)}
      end

    %{
      key:
        "page:#{page.path_fr}:#{System.system_time(:millisecond)}:#{System.unique_integer([:positive])}",
      kind: "page",
      area_code: page.area_code,
      page_path: page.path_fr,
      priority: 10,
      text_x: x,
      text_linkedin: li,
      link_x: link_x,
      link_linkedin: link_li,
      image_url: Seo.image(page.path_fr),
      image_url_x: Seo.image(page.path_en)
    }
    |> Hashtags.add()
  end

  # The page's description (else its title), cut to fit X with the room the
  # hashtags and the link need, then a line before the link.
  @x_cta "Figures and sources:"

  defp first_x(page, link) do
    body =
      Enum.find([page.description_en, page.title_en], &(&1 not in [nil, ""])) || "Syli Atlas"

    room = Post.x_limit() - Post.x_length("", link) - String.length(@x_cta) - 2 - 30
    cut(body, room) <> "\n\n" <> @x_cta
  end

  defp first_linkedin(page) do
    [page.title_fr, page.description_fr, "Lien ci-dessous."]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n\n")
  end

  defp cut(text, room) do
    if String.length(text) <= room do
      text
    else
      text
      |> String.slice(0, room - 1)
      |> String.replace(~r/\s+\S*$/, "")
      |> Kernel.<>("…")
    end
  end

  defp link(path, source), do: Seo.url(path) <> "?utm_source=#{source}&utm_medium=social"
end
