defmodule SyliAtlas.Geo.French do
  @moduledoc """
  French needs an article before most country names: « la note du Sénégal »,
  « le PIB de la Côte d'Ivoire », « au Mali », « Le Kenya est noté B ».
  Templates written as « de %{name} » produced « de Sénégal ».

  `bindings/2` gives every form a template may need, so a translation picks
  the one its grammar asks for; English templates keep using `%{name}`:

  - `of_name`: du Sénégal, de la Côte d'Ivoire, de l'Égypte, des Comores, de Madagascar
  - `in_name`: au Sénégal, en Côte d'Ivoire, en Égypte, aux Comores, à Madagascar
  - `the_name` / `The_name`: le Sénégal / Le Sénégal, Madagascar
  - `e`: agreement of a participle (noté, notée, notés): "", "e" or "s"

  A name that is not listed (a region, a community, an English name) is used
  as it is, with « de » or « d' » and « à ».
  """

  # Article and gender of each name as written on the site (areas.json).
  @articles %{
    "Afrique" => {"l'", :f},
    "Afrique du Nord" => {"l'", :f},
    "Afrique de l'Ouest" => {"l'", :f},
    "Afrique centrale" => {"l'", :f},
    "Afrique de l'Est" => {"l'", :f},
    "Afrique australe" => {"l'", :f},
    "Afrique subsaharienne" => {"l'", :f},
    "Monde" => {"le", :m},
    "Algérie" => {"l'", :f},
    "Angola" => {"l'", :m},
    "Bénin" => {"le", :m},
    "Botswana" => {"le", :m},
    "Burkina Faso" => {"le", :m},
    "Burundi" => {"le", :m},
    "Cabo Verde" => {"le", :m},
    "Cameroun" => {"le", :m},
    "Centrafrique" => {"la", :f},
    "Tchad" => {"le", :m},
    "Comores" => {"les", :pl},
    "RD Congo" => {"la", :f},
    "Congo" => {"le", :m},
    "Côte d'Ivoire" => {"la", :f},
    "Djibouti" => {nil, :m},
    "Égypte" => {"l'", :f},
    "Guinée équatoriale" => {"la", :f},
    "Érythrée" => {"l'", :f},
    "Eswatini" => {"l'", :m},
    "Éthiopie" => {"l'", :f},
    "Gabon" => {"le", :m},
    "Gambie" => {"la", :f},
    "Ghana" => {"le", :m},
    "Guinée" => {"la", :f},
    "Guinée-Bissau" => {"la", :f},
    "Kenya" => {"le", :m},
    "Lesotho" => {"le", :m},
    "Liberia" => {"le", :m},
    "Libye" => {"la", :f},
    "Madagascar" => {nil, :f},
    "Malawi" => {"le", :m},
    "Mali" => {"le", :m},
    "Mauritanie" => {"la", :f},
    "Maurice" => {nil, :f},
    "Maroc" => {"le", :m},
    "Mozambique" => {"le", :m},
    "Namibie" => {"la", :f},
    "Niger" => {"le", :m},
    "Nigeria" => {"le", :m},
    "Rwanda" => {"le", :m},
    "Sao Tomé-et-Principe" => {nil, :m},
    "Sénégal" => {"le", :m},
    "Seychelles" => {"les", :pl},
    "Sierra Leone" => {"la", :f},
    "Somalie" => {"la", :f},
    "Afrique du Sud" => {"l'", :f},
    "Soudan du Sud" => {"le", :m},
    "Soudan" => {"le", :m},
    "Tanzanie" => {"la", :f},
    "Togo" => {"le", :m},
    "Tunisie" => {"la", :f},
    "Ouganda" => {"l'", :m},
    "Zambie" => {"la", :f},
    "Zimbabwe" => {"le", :m}
  }

  # Names people search under, besides the one shown (titles, JSON-LD).
  @usual %{"Cabo Verde" => "Cap-Vert"}

  @doc "Every name the site shows with an article."
  def known, do: Map.keys(@articles)

  @doc "The other name a country is searched under, or nil."
  def usual_name(name), do: @usual[name]

  @doc "Bindings for a template that names `name`, in `locale`."
  def bindings(name, "fr") do
    [
      name: name,
      of_name: of(name),
      in_name: in_(name),
      the_name: the(name),
      The_name: capitalize(the(name)),
      e: agreement(name)
    ]
  end

  def bindings(name, _locale),
    do: [name: name, of_name: name, in_name: name, the_name: name, The_name: name, e: ""]

  @doc "« du Sénégal », « de la Côte d'Ivoire », « de l'Égypte », « des Comores », « de Madagascar »."
  def of(name) do
    case @articles[name] do
      {"le", _} -> "du " <> name
      {"la", _} -> "de la " <> name
      {"l'", _} -> "de l'" <> name
      {"les", _} -> "des " <> name
      _ -> if(vowel?(name), do: "d'" <> name, else: "de " <> name)
    end
  end

  @doc "« au Sénégal », « en Côte d'Ivoire », « aux Comores », « à Madagascar »."
  def in_(name) do
    case @articles[name] do
      {"le", _} -> "au " <> name
      {"les", _} -> "aux " <> name
      {a, _} when a in ["la", "l'"] -> "en " <> name
      _ -> "à " <> name
    end
  end

  @doc "« le Sénégal », « la Côte d'Ivoire », « l'Égypte », « les Comores », « Madagascar »."
  def the(name) do
    case @articles[name] do
      {"l'", _} -> "l'" <> name
      {a, _} when is_binary(a) -> a <> " " <> name
      _ -> name
    end
  end

  defp agreement(name) do
    case @articles[name] do
      {_, :f} -> "e"
      {_, :pl} -> "s"
      _ -> ""
    end
  end

  defp capitalize(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest
  defp capitalize(""), do: ""

  defp vowel?(name),
    do:
      name
      |> String.normalize(:nfd)
      |> String.first()
      |> String.downcase()
      |> Kernel.in(~w(a e i o u y))
end
