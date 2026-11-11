defmodule SyliAtlasWeb.CodeHighlightTest do
  use ExUnit.Case, async: true
  alias SyliAtlasWeb.CodeHighlight

  defp text(lines),
    do: Enum.map_join(lines, "\n", fn line -> Enum.map_join(line, "", &elem(&1, 1)) end)

  test "every character is kept, in every language" do
    for {source, lang} <- [
          {~s({\n  "a": [1.5, -2],\n  "b": null, "c": "x : y" …\n}), :json},
          {~s($ curl -O "https://syliatlas.com/api/v1/areas/CIV/csv"), :shell},
          {~s|=IMPORTDATA("https://syliatlas.com/api/v1/areas/CIV/csv")|, :shell},
          {"# Source: IMF\nyear,status,real_gdp_index\n2015,actual,100.0", :csv},
          {~s|import pandas as pd\n\ndf = pd.read_csv(url, comment="#")\nprint(df)|, :code},
          {~s|const res = await fetch("https://x/api");\n// comment|, :code}
        ] do
      lines = CodeHighlight.lines(source, lang)
      assert text(lines) == String.replace(source, "\n\n", "\n \n")
    end
  end

  test "JSON: keys, strings, numbers, keywords" do
    [[_, {"key", ~s("a")}, {"punc", ":"}, _, {"num", "1.5"}, _, _, {"kw", "null"}, _]] =
      CodeHighlight.lines(~s(  "a": 1.5, null,), :json)
  end

  test "CSV: the header row and the source comment" do
    [[{"com", "# Source"}], header, row] =
      CodeHighlight.lines("# Source\nyear,status\n2015,actual", :csv)

    assert [{"key", "year"}, {"punc", ","}, {"key", "status"}] = header
    assert [{"num", "2015"}, {"punc", ","}, {"str", "actual"}] = row
  end

  test "a '#' inside a string is not a comment" do
    [[_ | rest]] = CodeHighlight.lines(~s|df = pd.read_csv(url, comment="#")|, :code)
    assert {"str", ~s("#")} in rest
    refute Enum.any?(rest, &(elem(&1, 0) == "com"))
  end
end
