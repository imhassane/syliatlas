defmodule SyliAtlas.Geo.FrenchTest do
  use ExUnit.Case, async: true

  alias SyliAtlas.Geo.French

  test "the article each country name takes in French" do
    assert French.of("Sénégal") == "du Sénégal"
    assert French.of("Côte d'Ivoire") == "de la Côte d'Ivoire"
    assert French.of("Égypte") == "de l'Égypte"
    assert French.of("Afrique du Sud") == "de l'Afrique du Sud"
    assert French.of("Comores") == "des Comores"
    assert French.of("Madagascar") == "de Madagascar"
    assert French.of("Ouganda") == "de l'Ouganda"

    assert French.in_("Sénégal") == "au Sénégal"
    assert French.in_("Côte d'Ivoire") == "en Côte d'Ivoire"
    assert French.in_("Seychelles") == "aux Seychelles"
    assert French.in_("Maurice") == "à Maurice"

    assert French.the("Mali") == "le Mali"
    assert French.the("Égypte") == "l'Égypte"
    assert French.the("Djibouti") == "Djibouti"
  end

  test "a name not listed keeps « de » or « d' »" do
    assert French.of("CEDEAO") == "de CEDEAO"
    assert French.of("Abuja") == "d'Abuja"
  end

  test "every country of the site has its article" do
    names =
      Path.expand("../../../priv/data/areas.json", __DIR__)
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("areas")
      |> Enum.map(& &1["name_fr"])

    assert names -- French.known() == []
  end

  test "bindings: French forms, English names unchanged" do
    fr = French.bindings("Côte d'Ivoire", "fr")
    assert fr[:of_name] == "de la Côte d'Ivoire"
    assert fr[:The_name] == "La Côte d'Ivoire"
    assert fr[:e] == "e"

    en = French.bindings("Senegal", "en")
    assert en[:of_name] == "Senegal"
    assert en[:The_name] == "Senegal"
  end
end
