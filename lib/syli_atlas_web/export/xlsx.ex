defmodule SyliAtlasWeb.Export.Xlsx do
  @moduledoc """
  A minimal Excel (.xlsx) writer: a few sheets of text and numbers, the
  first row in bold. An .xlsx file is a zip of XML parts (Office Open XML);
  Erlang's `:zip` builds it in memory, so no dependency is needed.

  Text is written as inline strings (no shared-strings table), numbers as
  numbers: Excel, LibreOffice and Google Sheets show them in the reader's
  own number format.
  """

  @doc """
  The file's bytes. `sheets` is a list of `{name, rows, widths}`: rows are
  lists of cells (`nil`, a number or a string), widths the column widths in
  characters.
  """
  def build(sheets) when is_list(sheets) and sheets != [] do
    sheets = Enum.map(sheets, fn {name, rows, widths} -> {sheet_name(name), rows, widths} end)

    parts =
      [
        {"[Content_Types].xml", content_types(length(sheets))},
        {"_rels/.rels", root_rels()},
        {"xl/workbook.xml", workbook(sheets)},
        {"xl/_rels/workbook.xml.rels", workbook_rels(length(sheets))},
        {"xl/styles.xml", styles()}
      ] ++
        (sheets
         |> Enum.with_index(1)
         |> Enum.map(fn {{_name, rows, widths}, i} ->
           {"xl/worksheets/sheet#{i}.xml", worksheet(rows, widths)}
         end))

    files = Enum.map(parts, fn {path, xml} -> {String.to_charlist(path), xml} end)
    {:ok, {_name, bytes}} = :zip.create(~c"export.xlsx", files, [:memory])
    bytes
  end

  @xml ~s(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n)
  @main "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
  @rel "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  @pkg "http://schemas.openxmlformats.org/package/2006/relationships"

  defp content_types(n) do
    sheets =
      for i <- 1..n do
        ~s(<Override PartName="/xl/worksheets/sheet#{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>)
      end

    @xml <>
      ~s(<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">) <>
      ~s(<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>) <>
      ~s(<Default Extension="xml" ContentType="application/xml"/>) <>
      ~s(<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>) <>
      ~s(<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>) <>
      Enum.join(sheets) <> "</Types>"
  end

  defp root_rels do
    @xml <>
      ~s(<Relationships xmlns="#{@pkg}">) <>
      ~s(<Relationship Id="rId1" Type="#{@rel}/officeDocument" Target="xl/workbook.xml"/>) <>
      "</Relationships>"
  end

  defp workbook(sheets) do
    entries =
      sheets
      |> Enum.with_index(1)
      |> Enum.map(fn {{name, _, _}, i} ->
        ~s(<sheet name="#{escape(name)}" sheetId="#{i}" r:id="rId#{i}"/>)
      end)

    @xml <>
      ~s(<workbook xmlns="#{@main}" xmlns:r="#{@rel}"><sheets>) <>
      Enum.join(entries) <> "</sheets></workbook>"
  end

  defp workbook_rels(n) do
    sheets =
      for i <- 1..n do
        ~s(<Relationship Id="rId#{i}" Type="#{@rel}/worksheet" Target="worksheets/sheet#{i}.xml"/>)
      end

    @xml <>
      ~s(<Relationships xmlns="#{@pkg}">) <>
      Enum.join(sheets) <>
      ~s(<Relationship Id="rId#{n + 1}" Type="#{@rel}/styles" Target="styles.xml"/>) <>
      "</Relationships>"
  end

  # Two cell formats: 0 normal, 1 bold (the header row).
  defp styles do
    @xml <>
      ~s(<styleSheet xmlns="#{@main}">) <>
      ~s(<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>) <>
      ~s(<font><b/><sz val="11"/><name val="Calibri"/></font></fonts>) <>
      ~s(<fills count="2"><fill><patternFill patternType="none"/></fill>) <>
      ~s(<fill><patternFill patternType="gray125"/></fill></fills>) <>
      ~s(<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>) <>
      ~s(<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>) <>
      ~s(<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>) <>
      ~s(<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>) <>
      "</styleSheet>"
  end

  defp worksheet(rows, widths) do
    cols =
      case widths do
        [] ->
          ""

        widths ->
          "<cols>" <>
            (widths
             |> Enum.with_index(1)
             |> Enum.map_join(fn {w, i} ->
               ~s(<col min="#{i}" max="#{i}" width="#{w}" customWidth="1"/>)
             end)) <> "</cols>"
      end

    data =
      rows
      |> Enum.with_index(1)
      |> Enum.map_join(fn {cells, r} ->
        style = if r == 1, do: ~s( s="1"), else: ""

        ~s(<row r="#{r}">) <>
          (cells
           |> Enum.with_index()
           |> Enum.map_join(fn {cell, c} -> cell(cell, column(c) <> "#{r}", style) end)) <>
          "</row>"
      end)

    @xml <>
      ~s(<worksheet xmlns="#{@main}">) <>
      cols <> "<sheetData>" <> data <> "</sheetData></worksheet>"
  end

  defp cell(nil, _ref, _style), do: ""

  defp cell(n, ref, style) when is_integer(n) or is_float(n),
    do: ~s(<c r="#{ref}"#{style}><v>#{number(n)}</v></c>)

  defp cell(text, ref, style) when is_binary(text),
    do:
      ~s(<c r="#{ref}"#{style} t="inlineStr"><is><t xml:space="preserve">#{escape(text)}</t></is></c>)

  defp number(n) when is_integer(n), do: Integer.to_string(n)
  defp number(n), do: :erlang.float_to_binary(n, [:short])

  @doc "Column letters of a 0-based index: 0 → A, 25 → Z, 26 → AA."
  def column(i) when i < 26, do: <<?A + i>>
  def column(i), do: column(div(i, 26) - 1) <> column(rem(i, 26))

  # Excel refuses sheet names longer than 31 characters or with []:*?/\.
  defp sheet_name(name),
    do: name |> String.replace(~r{[\[\]:*?/\\]}, " ") |> String.slice(0, 31)

  # XML text: the five escapes, and no control characters (forbidden in XML 1.0).
  defp escape(text) do
    text
    |> String.replace(~r/[\x00-\x08\x0B\x0C\x0E-\x1F]/, "")
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
