defmodule SyliAtlas.Accounts.EmailLayout do
  @moduledoc """
  The HTML and plain text of every email sent to people, after the
  « E-mails » boards of the Syli Atlas canvas: the logo, one white card
  under a thin sunset rule, a monospace eyebrow, a large light title, the
  content, then the button.

  The plain text is the reference (tests read it); the HTML is built from
  the same parts. Templates are EEx with HTML escaping, never HEEx (which
  adds attributes meant for LiveView). Email clients ignore CSS variables,
  `<style>` blocks and SVG: colours are inline hex, the layout is tables,
  the mark is a PNG beside the wordmark in text. Codes and addresses stay left to right.

      EmailLayout.render(
        language: "fr",
        preheader: "...",
        eyebrow: "Connexion",
        title: "Votre code de connexion",
        blocks: [{:paragraph, "..."}, {:code, "482913", "Valable 10 minutes"}],
        button: {"Ouvrir mon espace", url},
        footer: [{"Gérer mes alertes", url}]
      )
  """

  use Gettext, backend: SyliAtlasWeb.Gettext

  require EEx

  # The Sily palette (light theme): each text pair passes 4.5:1 on its background.
  @colors %{
    page: "#F3F4F8",
    card: "#FFFFFF",
    border: "#E4E6EF",
    ink: "#11132B",
    ink_muted: "#4A4E66",
    ink_subtle: "#5B607A",
    brand: "#4B3BFF",
    on_brand: "#FFFFFF",
    code_bg: "#EEF0FB",
    note_bg: "#FFF4E5",
    note_ink: "#8A4B00",
    sunset_fallback: "#FF6B3D"
  }

  @sunset "linear-gradient(90deg, #FFB547, #FF6B3D, #F0347A, #8A3FFC, #3B6CFF)"
  @sans "'Inter Tight', -apple-system, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif"
  @mono "'JetBrains Mono', ui-monospace, Menlo, Consolas, monospace"

  @type block ::
          {:paragraph, String.t()}
          | {:code, String.t(), String.t()}
          | {:note, String.t()}
          | {:facts, [{String.t(), String.t()}]}
          | {:section, String.t(), {String.t(), String.t()} | nil}
          | {:highlight, String.t()}
          | {:figures, String.t(), [{String.t(), String.t()}]}
          | {:small, String.t()}

  @doc "The HTML document."
  @spec render(keyword()) :: String.t()
  def render(opts) do
    assigns = %{
      lang: Keyword.fetch!(opts, :language),
      preheader: Keyword.get(opts, :preheader, ""),
      eyebrow: Keyword.fetch!(opts, :eyebrow),
      title: Keyword.fetch!(opts, :title),
      blocks: Keyword.get(opts, :blocks, []),
      button: Keyword.get(opts, :button),
      footer: Keyword.get(opts, :footer, []),
      logo_url: SyliAtlasWeb.Endpoint.url() <> "/images/email-mark.png",
      tagline: dgettext("emails", "Syli Atlas · African economies, every figure sourced."),
      automatic: dgettext("emails", "This email was sent automatically: replies are not read."),
      c: @colors,
      sunset: @sunset,
      sans: @sans,
      mono: @mono
    }

    assigns |> document() |> Phoenix.HTML.safe_to_string()
  end

  @doc "The plain-text body, from the same parts."
  @spec text(keyword()) :: String.t()
  def text(opts) do
    blocks = Enum.map(Keyword.get(opts, :blocks, []), &text_block/1)

    button =
      case Keyword.get(opts, :button) do
        {label, url} -> ["#{label} : #{url}"]
        nil -> []
      end

    footer = Enum.map(Keyword.get(opts, :footer, []), fn {label, url} -> "#{label} : #{url}" end)

    ([Keyword.fetch!(opts, :title), ""] ++
       Enum.intersperse(blocks, "") ++
       if(button == [], do: [], else: ["" | button]) ++
       ["", "--", dgettext("emails", "Syli Atlas · African economies, every figure sourced.")] ++
       footer)
    |> Enum.join("\n")
  end

  defp text_block({:paragraph, text}), do: text
  defp text_block({:code, code, caption}), do: "    #{code}\n#{caption}"
  defp text_block({:note, text}), do: "! " <> text

  defp text_block({:section, title, nil}), do: "## " <> title

  defp text_block({:section, title, {label, url}}), do: "## #{title}\n#{label} : #{url}"

  defp text_block({:highlight, text}), do: "> " <> text
  defp text_block({:small, text}), do: text

  defp text_block({:figures, caption, figures}),
    do:
      caption <>
        "\n" <> Enum.map_join(figures, "\n", fn {label, value} -> "#{label} : #{value}" end)

  defp text_block({:facts, facts}),
    do: Enum.map_join(facts, "\n", fn {label, value} -> "#{label} : #{value}" end)

  table = ~s(role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0")

  EEx.function_from_string(
    :defp,
    :document,
    """
    <!DOCTYPE html>
    <html lang="<%= @lang %>">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="color-scheme" content="light">
    <meta name="supported-color-schemes" content="light">
    <title><%= @title %></title>
    </head>
    <body style="margin: 0; padding: 0; background: <%= @c.page %>;">
    <div style="display: none; max-height: 0; overflow: hidden; opacity: 0;"><%= @preheader %></div>
    <table #{table} bgcolor="<%= @c.page %>" style="background: <%= @c.page %>;">
    <tr><td align="center" style="padding: 32px 16px;">
    <table #{table} style="max-width: 560px; font-family: <%= @sans %>; color: <%= @c.ink %>;">
    <tr><td align="left" style="padding: 0 4px 24px;">
    <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr><td style="padding-right: 10px;"><img src="<%= @logo_url %>" width="28" height="28" alt="" style="display: block; border: 0;"></td><td style="font-family: <%= @sans %>; font-size: 20px; font-weight: 600; letter-spacing: -0.02em; color: <%= @c.ink %>;">syli <span style="font-weight: 400; color: <%= @c.ink_muted %>;">atlas</span></td></tr></table>
    </td></tr>
    <tr><td bgcolor="<%= @c.card %>" style="background: <%= @c.card %>; border: 1px solid <%= @c.border %>; border-radius: 8px; overflow: hidden;">
    <div style="height: 3px; line-height: 3px; font-size: 0; background: <%= @c.sunset_fallback %>; background-image: <%= @sunset %>;">&nbsp;</div>
    <table #{table}>
    <tr><td align="left" style="padding: 36px 32px 32px;">
    <p style="margin: 0 0 16px; font-family: <%= @mono %>; font-size: 13px; line-height: 1.4; font-weight: 500; letter-spacing: 0.06em; text-transform: uppercase; color: <%= @c.brand %>;"><%= @eyebrow %></p>
    <h1 style="margin: 0 0 20px; font-size: 32px; line-height: 1.15; font-weight: 300; letter-spacing: -0.02em; color: <%= @c.ink %>;"><%= @title %></h1>
    <%= for block <- @blocks do %><%= block(block, assigns) %><% end %>
    <%= if @button do %><%= button(@button, assigns) %><% end %>
    </td></tr>
    </table>
    </td></tr>
    <tr><td align="left" style="padding: 24px 4px 0;">
    <%= if @footer != [] do %><p style="margin: 0 0 8px; font-size: 12px; line-height: 1.5; color: <%= @c.ink_subtle %>;"><%= for {{label, url}, i} <- Enum.with_index(@footer) do %><%= if i > 0 do %> · <% end %><a href="<%= url %>" style="color: <%= @c.brand %>;"><%= label %></a><% end %></p><% end %>
    <p style="margin: 0 0 4px; font-size: 12px; line-height: 1.5; color: <%= @c.ink_subtle %>;"><%= @tagline %></p>
    <p style="margin: 0; font-size: 12px; line-height: 1.5; color: <%= @c.ink_subtle %>;"><%= @automatic %></p>
    </td></tr>
    </table>
    </td></tr>
    </table>
    </body>
    </html>
    """,
    [:assigns],
    engine: Phoenix.HTML.Engine
  )

  EEx.function_from_string(
    :defp,
    :block_html,
    """
    <%= case @block do %><% {:paragraph, text} -> %><p style="margin: 0 0 16px; font-size: 16px; line-height: 1.6; color: <%= @c.ink %>;"><%= text %></p><% {:code, code, caption} -> %><table #{table} style="margin: 8px 0 20px;"><tr><td bgcolor="<%= @c.code_bg %>" style="background: <%= @c.code_bg %>; border-radius: 8px; padding: 20px 24px;">
    <p dir="ltr" style="margin: 0; font-family: <%= @mono %>; font-size: 36px; line-height: 1.2; letter-spacing: 0.18em; font-weight: 500; color: <%= @c.ink %>;"><%= code %></p>
    <p style="margin: 6px 0 0; font-size: 13px; line-height: 1.4; color: <%= @c.ink_muted %>;"><%= caption %></p>
    </td></tr></table><% {:note, text} -> %><table #{table} style="margin: 8px 0 16px;"><tr><td bgcolor="<%= @c.note_bg %>" style="background: <%= @c.note_bg %>; border-radius: 8px; padding: 14px 16px; font-size: 14px; line-height: 1.5; color: <%= @c.note_ink %>;"><%= text %></td></tr></table><% {:section, title, link} -> %><table #{table} style="margin: 32px 0 12px; border-top: 1px solid <%= @c.border %>;"><tr><td align="left" style="padding-top: 24px; font-family: <%= @sans %>; font-size: 24px; line-height: 1.2; font-weight: 400; letter-spacing: -0.015em; color: <%= @c.ink %>;"><%= title %></td><%= if link do %><td align="right" style="padding-top: 24px; font-size: 14px; white-space: nowrap;"><a href="<%= elem(link, 1) %>" style="color: <%= @c.brand %>; font-weight: 500; text-decoration: none;"><%= elem(link, 0) %> →</a></td><% end %></tr></table><% {:highlight, text} -> %><table #{table} style="margin: 4px 0 12px;"><tr><td bgcolor="<%= @c.code_bg %>" style="background: <%= @c.code_bg %>; border-radius: 8px; padding: 12px 14px; font-size: 15px; line-height: 1.5; color: <%= @c.ink %>;"><%= text %></td></tr></table><% {:small, text} -> %><p style="margin: 16px 0 0; font-size: 12px; line-height: 1.5; color: <%= @c.ink_subtle %>;"><%= text %></p><% {:figures, caption, figures} -> %><p style="margin: 8px 0 8px; font-family: <%= @mono %>; font-size: 11px; line-height: 1.4; font-weight: 500; letter-spacing: 0.07em; text-transform: uppercase; color: <%= @c.ink_subtle %>;"><%= caption %></p><table #{table} style="margin: 0 0 8px; border-collapse: separate; border-spacing: 6px 0;"><tr><%= for {label, value} <- figures do %><td bgcolor="<%= @c.page %>" style="background: <%= @c.page %>; border-radius: 8px; padding: 10px 12px; width: 33%;"><p style="margin: 0; font-size: 12px; line-height: 1.4; color: <%= @c.ink_muted %>;"><%= label %></p><p style="margin: 2px 0 0; font-size: 20px; line-height: 1.3; font-weight: 500; color: <%= @c.ink %>;"><%= value %></p></td><% end %></tr></table><% {:facts, facts} -> %><table #{table} style="margin: 4px 0 20px; border-collapse: collapse;"><%= for {label, value} <- facts do %><tr><td style="padding: 10px 0; border-top: 1px solid <%= @c.border %>; font-size: 14px; color: <%= @c.ink_subtle %>;"><%= label %></td><td align="right" style="padding: 10px 0; border-top: 1px solid <%= @c.border %>; font-size: 15px; color: <%= @c.ink %>;"><%= value %></td></tr><% end %></table><% end %>
    """,
    [:assigns],
    engine: Phoenix.HTML.Engine
  )

  defp block(block, assigns), do: block_html(Map.put(assigns, :block, block))

  EEx.function_from_string(
    :defp,
    :button_html,
    """
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin: 28px 0 0;"><tr><td align="right">
    <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr><td bgcolor="<%= @c.brand %>" style="background: <%= @c.brand %>; border-radius: 999px;">
    <a href="<%= @url %>" style="display: inline-block; padding: 13px 24px; font-family: <%= @sans %>; font-size: 15px; font-weight: 500; line-height: 1.2; color: <%= @c.on_brand %>; text-decoration: none;"><%= @label %></a>
    </td></tr></table>
    </td></tr></table>
    """,
    [:assigns],
    engine: Phoenix.HTML.Engine
  )

  defp button({label, url}, assigns),
    do: button_html(Map.merge(assigns, %{label: label, url: url}))
end
