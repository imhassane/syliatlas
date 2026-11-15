defmodule SyliAtlasWeb.TranslationsTest do
  @moduledoc """
  Every interface text has a French translation, none left fuzzy; every text
  of the public pages is translated in the five other languages.

  Sign-in, member space, recap sign-up and administration stay in English for
  es, pt, ar, hi and zh (the public pages of those languages link there in
  English), so their texts may be left empty.
  """
  use ExUnit.Case, async: true

  @dir Path.expand("../../priv/gettext", __DIR__)
  @others ~w(es pt ar hi zh)
  @private ~r/account|session|recap|unsubscribe|admin|mailer|passkey|auth\.ex/

  test "French catalog is complete" do
    po = File.read!(Path.join(@dir, "fr/LC_MESSAGES/default.po"))

    refute po =~ ~r/^#,.*\bfuzzy\b/m,
           "fuzzy translations are never kept: check them and remove the flag"

    missing =
      ~r/msgid "(.+)"\nmsgstr ""\n/
      |> Regex.scan(po)
      |> Enum.map(fn [_, id] -> id end)

    assert missing == [], "missing French translations:\n" <> Enum.join(missing, "\n")
  end

  for locale <- @others do
    test "#{locale}: every text of the public pages is translated" do
      po = Expo.PO.parse_file!(Path.join(@dir, unquote(locale) <> "/LC_MESSAGES/default.po"))

      missing =
        for m <- po.messages, public?(m), untranslated?(m), do: IO.iodata_to_binary(m.msgid)

      assert missing == [],
             "missing #{unquote(locale)} translations on public pages:\n" <>
               Enum.join(missing, "\n")
    end
  end

  test "no French spacing before a colon outside French" do
    for locale <- ["en" | @others] do
      po = Expo.PO.parse_file!(Path.join(@dir, locale <> "/LC_MESSAGES/default.po"))

      bad =
        for %Expo.Message.Singular{} = m <- po.messages,
            str = IO.iodata_to_binary(m.msgstr),
            str =~ ~r/\p{L} :(\s|$)/u,
            do: str

      assert bad == [], "#{locale}: space before « : »:\n" <> Enum.join(bad, "\n")
    end
  end

  defp public?(m) do
    files = for {file, _line} <- m.references |> List.flatten(), do: file

    files != [] and not Enum.all?(files, &(&1 =~ @private))
  end

  defp untranslated?(%Expo.Message.Singular{msgstr: s}), do: IO.iodata_to_binary(s) == ""

  defp untranslated?(%Expo.Message.Plural{msgstr: forms}),
    do: Enum.any?(forms, fn {_, s} -> IO.iodata_to_binary(s) == "" end)
end
