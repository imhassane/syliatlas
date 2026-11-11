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
        "logo" => url("/images/apple-touch-icon.png")
      }
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

  def dataset(name, area_name, path, edition) do
    %{
      "@context" => "https://schema.org",
      "@type" => "Dataset",
      "name" => name,
      "spatialCoverage" => area_name,
      "temporalCoverage" => "2015/2030",
      "isBasedOn" => "IMF, #{edition["label"]}",
      "dateModified" => edition["fetched_at"],
      "url" => url(path),
      "distribution" => [
        %{
          "@type" => "DataDownload",
          "encodingFormat" => "application/json",
          "contentUrl" => url(path)
        }
      ]
    }
  end
end
