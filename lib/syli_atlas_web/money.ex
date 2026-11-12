defmodule SyliAtlasWeb.Money do
  @moduledoc """
  Amounts in the reader's currency (canvas « Sélecteur de devise »).

  The server writes every amount in its own currency, as published (dollars
  for the IMF and the World Bank, the exchange's currency for a session),
  wrapped by `amount/2`. The currency menu of the header
  (`SyliAtlasWeb.Layouts`, `assets/js/ui/money.js`) rewrites them in the
  reader's choice, the original amount under it in small:

    * by default the currency of the country the reader is in (Cloudflare's
      header, asked once at `/visitor`), as for the language;
    * a choice made in the menu is kept on the device and wins;
    * « original currencies » shows every amount as published.

  Rules: an annual amount (`year:`) is converted at the average rate of its
  year, never at today's: when we hold no rate for that year it stays as
  published. A dated amount (a session) is converted at the latest rate.
  Rates, ratios and percentages are never converted: only amounts.

  The rates come with the page (units per US dollar, `client_rates/0`): no
  request, and no API.
  """
  use Gettext, backend: SyliAtlasWeb.Gettext

  alias SyliAtlas.Economy.Currencies
  alias SyliAtlas.Fx

  @majors ~w(USD EUR CNY)

  @doc """
  An amount the currency menu can rewrite: `text` is how the server writes
  it (kept when there is no script or no rate). Options: `year:` for an
  annual amount, `scale:` when `value` is in thousands, millions, billions.
  """
  def amount(text, opts) do
    case {Keyword.get(opts, :value), Keyword.fetch!(opts, :currency)} do
      {v, _currency} when not is_number(v) ->
        text

      {v, currency} ->
        value = v * Keyword.get(opts, :scale, 1)
        year = Keyword.get(opts, :year)

        Phoenix.HTML.raw([
          ~s(<span class="money" data-money="),
          :erlang.float_to_binary(value * 1.0, [:short]),
          ~s(" data-currency="),
          escape(currency),
          ~s("),
          if(year, do: [~s( data-year="), to_string(year), ~s(")], else: []),
          ~s(><span data-money-main>),
          escape(text),
          ~s(</span><span class="money-local" data-money-local hidden></span></span>)
        ])
    end
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  @doc """
  The currencies of the menus: the three references, then the African
  currencies by name, each with its countries (shown and searched).
  """
  def options(locale) do
    names =
      for %{type: :country} = e <- SyliAtlasWeb.Search.Index.get(),
          into: %{},
          do: {e.code, SyliAtlas.Locales.pick(e.names, locale)}

    majors =
      for code <- @majors,
          do: %{code: code, name: major_name(code), countries: [], country_names: []}

    african =
      for code <- Currencies.codes() do
        countries = Currencies.countries_using(code)

        %{
          code: code,
          name: Currencies.name_of(code, locale),
          countries: countries,
          country_names:
            Enum.map(countries, &(names[&1] || SyliAtlas.Geo.Names.name(&1, locale) || &1))
        }
      end
      |> Enum.sort_by(&String.normalize(String.downcase(&1.name), :nfd))

    majors ++ african
  end

  def major_name("USD"), do: gettext("US dollar")
  def major_name("EUR"), do: gettext("euro")
  def major_name("CNY"), do: gettext("Chinese yuan")

  @doc "A short symbol for the three references, else the code."
  def symbol("USD"), do: "$"
  def symbol("EUR"), do: "€"
  def symbol("CNY"), do: "¥"
  # Shared by several countries: no single flag stands for them.
  def symbol(code) when code in ~w(XOF XAF), do: "CFA"
  def symbol(code), do: code

  @doc """
  The rates the page carries, as JSON: latest (`rates`), averages of each
  year (`years`), units per US dollar. Built once per data version.
  """
  def client_rates do
    version = SyliAtlas.Market.data_version()

    case :persistent_term.get({__MODULE__, :rates}, nil) do
      {^version, json} ->
        json

      _ ->
        json = build_rates(Fx.latest())
        :persistent_term.put({__MODULE__, :rates}, {version, json})
        json
    end
  end

  defp build_rates(nil), do: nil

  defp build_rates(doc) do
    Jason.encode!(%{
      "as_of" => doc["as_of"],
      "rates" => doc["rates"] || %{},
      "years" => doc["year_avg"] || %{}
    })
  end
end
