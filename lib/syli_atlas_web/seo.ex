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
