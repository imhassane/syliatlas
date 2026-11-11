defmodule SyliAtlasWeb.TranslationsTest do
  @moduledoc "Every interface text has a French translation, none left fuzzy."
  use ExUnit.Case, async: true

  @po Path.expand("../../priv/gettext/fr/LC_MESSAGES/default.po", __DIR__)

  test "French catalog is complete" do
    po = File.read!(@po)

    refute po =~ ~r/^#,.*\bfuzzy\b/m,
           "fuzzy translations are never kept: check them and remove the flag"

    missing =
      ~r/msgid "(.+)"\nmsgstr ""\n/
      |> Regex.scan(po)
      |> Enum.map(fn [_, id] -> id end)

    assert missing == [], "missing French translations:\n" <> Enum.join(missing, "\n")
  end
end
