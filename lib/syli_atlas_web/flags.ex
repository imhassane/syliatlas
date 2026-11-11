defmodule SyliAtlasWeb.Flags do
  @moduledoc """
  Flags of the 54 African countries, from flag-icons (MIT, priv/flags/LICENSE),
  built by scripts/build_flags.py.

  Two ways to show one, to keep pages light:

    * `inline/1`: the SVG itself, written into the page (a country page shows
      one flag: no request, painted with the title; median 0.5 KB, Egypt 8.7 KB);
    * `sprite_href/1`: a <use> reference into priv/static/images/flags.svg,
      one file for every flag (22 KB compressed), cached for good and by the
      service worker, loaded only by pages that show several flags.

  Flags are decorative: the country's name is always written next to them.
  """
  use Phoenix.VerifiedRoutes,
    endpoint: SyliAtlasWeb.Endpoint,
    router: SyliAtlasWeb.Router,
    statics: SyliAtlasWeb.static_paths()

  @iso2 %{
    "DZA" => "dz",
    "AGO" => "ao",
    "BEN" => "bj",
    "BWA" => "bw",
    "BFA" => "bf",
    "BDI" => "bi",
    "CPV" => "cv",
    "CMR" => "cm",
    "CAF" => "cf",
    "TCD" => "td",
    "COM" => "km",
    "COG" => "cg",
    "COD" => "cd",
    "CIV" => "ci",
    "DJI" => "dj",
    "EGY" => "eg",
    "GNQ" => "gq",
    "ERI" => "er",
    "SWZ" => "sz",
    "ETH" => "et",
    "GAB" => "ga",
    "GMB" => "gm",
    "GHA" => "gh",
    "GIN" => "gn",
    "GNB" => "gw",
    "KEN" => "ke",
    "LSO" => "ls",
    "LBR" => "lr",
    "LBY" => "ly",
    "MDG" => "mg",
    "MWI" => "mw",
    "MLI" => "ml",
    "MRT" => "mr",
    "MUS" => "mu",
    "MAR" => "ma",
    "MOZ" => "mz",
    "NAM" => "na",
    "NER" => "ne",
    "NGA" => "ng",
    "RWA" => "rw",
    "STP" => "st",
    "SEN" => "sn",
    "SYC" => "sc",
    "SLE" => "sl",
    "SOM" => "so",
    "ZAF" => "za",
    "SSD" => "ss",
    "SDN" => "sd",
    "TZA" => "tz",
    "TGO" => "tg",
    "TUN" => "tn",
    "UGA" => "ug",
    "ZMB" => "zm",
    "ZWE" => "zw"
  }

  @dir Path.join([__DIR__, "..", "..", "priv", "flags"]) |> Path.expand()

  @svgs (for {iso3, cc} <- @iso2, into: %{} do
           path = Path.join(@dir, cc <> ".svg")
           @external_resource path
           svg =
             path
             |> File.read!()
             |> String.trim()
             |> String.replace(
               "<svg ",
               ~s(<svg class="flag-svg" aria-hidden="true" focusable="false" preserveAspectRatio="xMidYMid slice" ),
               global: false
             )

           {iso3, svg}
         end)

  @doc "The two-letter code used by the flag files, or nil."
  def iso2(iso3), do: Map.get(@iso2, iso3)

  @doc "The flag's SVG, safe to write into a page, or nil."
  def inline(iso3) do
    case Map.get(@svgs, iso3) do
      nil -> nil
      svg -> Phoenix.HTML.raw(svg)
    end
  end

  @doc "The address of the flag in the sprite (digested in production), or nil."
  def sprite_href(iso3) do
    case iso2(iso3) do
      nil -> nil
      cc -> ~p"/images/flags.svg" <> "#" <> cc
    end
  end
end
