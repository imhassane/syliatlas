defmodule SyliAtlasWeb.Seo do
  @moduledoc "Page metadata: canonical URL, language alternates, JSON-LD."
  use Gettext, backend: SyliAtlasWeb.Gettext

  def url(path), do: SyliAtlasWeb.Endpoint.url() <> path

  @doc "Builds the seo assign from localised paths %{\"fr\" => path, \"en\" => path}."
  def page(locale, paths, description, extra \\ %{}) do
    Map.merge(
      %{
        description: description,
        canonical: url(paths[locale]),
        image: image(paths[locale]),
        alternates: [
          {"fr", url(paths["fr"])},
          {"en", url(paths["en"])},
          {"x-default", url(paths["fr"])}
        ]
      },
      extra
    )
  end

  @doc """
  The share image of a page: drawn from its figures by
  `SyliAtlasWeb.OgImageController`. The version (code and data) is in the
  address, so an image is never changed, only replaced: caches keep it a year.
  """
  def image(path), do: url("/og/" <> SyliAtlasWeb.Build.version() <> path <> ".png")

  @doc """
  The site and its publisher (home page): `WebSite` with its search box and
  `Organization`, so search engines name the site and link its pages together.
  """
  def site(locale) do
    home = url("/" <> locale)

    [
      %{
        "@context" => "https://schema.org",
        "@type" => "WebSite",
        "@id" => url("/#website"),
        "name" => "Syli Atlas",
        "url" => home,
        "inLanguage" => locale,
        "publisher" => %{"@id" => url("/#organization")},
        "potentialAction" => %{
          "@type" => "SearchAction",
          "target" => %{
            "@type" => "EntryPoint",
            "urlTemplate" => url(SyliAtlasWeb.Paths.search(locale)) <> "?q={search_term_string}"
          },
          "query-input" => "required name=search_term_string"
        }
      },
      %{
        "@context" => "https://schema.org",
        "@type" => "Organization",
        "@id" => url("/#organization"),
        "name" => "Syli Atlas",
        "url" => url("/"),
        "logo" => url("/images/apple-touch-icon.png"),
        "description" =>
          gettext(
            "African economies in verifiable figures: every figure names its public source."
          )
      }
      |> put_if(
        "contactPoint",
        case Application.get_env(:syli_atlas, :site, [])[:contact_email] do
          nil -> nil
          email -> %{"@type" => "ContactPoint", "email" => email, "contactType" => "editorial"}
        end
      )
    ]
  end

  def alternates_for_header(paths), do: [{"fr", paths["fr"]}, {"en", paths["en"]}]

  def breadcrumbs(items) do
    %{
      "@context" => "https://schema.org",
      "@type" => "BreadcrumbList",
      "itemListElement" =>
        items
        |> Enum.with_index(1)
        |> Enum.map(fn {{name, path}, i} ->
          %{"@type" => "ListItem", "position" => i, "name" => name, "item" => url(path)}
        end)
    }
  end

  def faq(questions) do
    %{
      "@context" => "https://schema.org",
      "@type" => "FAQPage",
      "mainEntity" =>
        Enum.map(questions, fn {q, a} ->
          %{
            "@type" => "Question",
            "name" => q,
            "acceptedAnswer" => %{"@type" => "Answer", "text" => a}
          }
        end)
    }
  end

  @license "https://creativecommons.org/licenses/by/4.0/"

  @doc """
  The licence of what Syli Atlas computes and writes (totals, ranks, changes,
  sentences, images): CC BY 4.0. Source figures keep their source's terms;
  stock prices (MansaAPI) are not redistributable.
  """
  def license_url, do: @license

  @doc """
  A `Dataset` as Google Dataset Search reads it: a description, the page
  itself as `url`, its publisher and licence, the variables measured, the
  downloads. `opts`: `:name`, `:description`, `:path` (the page), `:area`
  (`%{name, code}`), `:keywords`, `:variables` ([{name, unit}]),
  `:downloads` ([{format, path}]), `:based_on` ({name, url}), `:modified`,
  `:temporal`, `:locale`.
  """
  def dataset(opts) do
    opts = Map.new(opts)
    locale = opts[:locale] || "fr"

    %{
      "@context" => "https://schema.org",
      "@type" => "Dataset",
      "name" => opts.name,
      "description" => opts.description,
      "url" => url(opts.path),
      "inLanguage" => locale,
      "isAccessibleForFree" => true,
      "creator" => %{"@id" => url("/#organization")},
      "publisher" => %{"@id" => url("/#organization")},
      "license" => license_url(),
      "creditText" => "Syli Atlas"
    }
    |> put_if("keywords", opts[:keywords])
    |> put_if("dateModified", opts[:modified])
    |> put_if("temporalCoverage", opts[:temporal])
    |> put_if("spatialCoverage", opts[:area] && place(opts.area))
    |> put_if("about", opts[:area] && opts.area[:code] && country(opts.area))
    |> put_if(
      "isBasedOn",
      case opts[:based_on] do
        {name, nil} -> %{"@type" => "CreativeWork", "name" => name}
        {name, href} -> %{"@type" => "CreativeWork", "name" => name, "url" => href}
        _ -> nil
      end
    )
    |> put_if(
      "variableMeasured",
      opts[:variables] &&
        Enum.map(opts.variables, fn {name, unit} ->
          %{"@type" => "PropertyValue", "name" => name, "unitText" => unit}
        end)
    )
    |> put_if(
      "distribution",
      opts[:downloads] &&
        Enum.map(opts.downloads, fn {format, path} ->
          %{"@type" => "DataDownload", "encodingFormat" => format, "contentUrl" => url(path)}
        end)
    )
  end

  defp place(area), do: %{"@type" => "Place", "name" => area.name}

  defp country(area) do
    %{"@type" => "Country", "name" => area.name, "identifier" => area.code}
    |> put_if("alternateName", area[:alternate])
  end

  @doc "A ranked list: `ItemList` of `{name, path}` in order."
  def item_list(name, items) do
    %{
      "@context" => "https://schema.org",
      "@type" => "ItemList",
      "name" => name,
      "numberOfItems" => length(items),
      "itemListElement" =>
        items
        |> Enum.with_index(1)
        |> Enum.map(fn {{item_name, path}, i} ->
          %{"@type" => "ListItem", "position" => i, "name" => item_name, "url" => url(path)}
        end)
    }
  end

  @doc "The method page: what the site is, where its figures come from."
  def about_page(name, path, sources) do
    %{
      "@context" => "https://schema.org",
      "@type" => "AboutPage",
      "name" => name,
      "url" => url(path),
      "about" => %{"@id" => url("/#organization")},
      "citation" =>
        for {source_name, href} <- sources do
          %{"@type" => "CreativeWork", "name" => source_name}
          |> put_if("url", href)
        end
    }
  end

  @doc "A listed company: `Corporation` with its ticker on its exchange."
  def corporation(name, ticker, exchange, path) do
    %{
      "@context" => "https://schema.org",
      "@type" => "Corporation",
      "name" => name,
      "tickerSymbol" => "#{exchange} #{ticker}",
      "url" => url(path)
    }
  end

  @doc "A community of states (ECOWAS, WAEMU…) and its members."
  def community(name, alternate, path, members) do
    %{
      "@context" => "https://schema.org",
      "@type" => "GovernmentOrganization",
      "name" => name,
      "alternateName" => alternate,
      "url" => url(path),
      "member" =>
        for({m, p} <- members, do: %{"@type" => "Country", "name" => m, "url" => url(p)})
    }
  end

  defp put_if(map, _key, nil), do: map
  defp put_if(map, _key, false), do: map
  defp put_if(map, _key, []), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)
end
