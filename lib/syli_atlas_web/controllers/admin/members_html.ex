defmodule SyliAtlasWeb.Admin.MembersHTML do
  use SyliAtlasWeb, :html

  import SyliAtlasWeb.AdminComponents, only: [admin_shell: 1, admin_pager: 1]
  import SyliAtlasWeb.Admin.Format, only: [int: 1]

  embed_templates "members_html/*"

  def mail_label("resend"), do: "Resend"
  def mail_label("smtp " <> where), do: "Mailpit (#{where})"
  def mail_label("local"), do: "Boîte locale (/dev/mailbox)"
  def mail_label("test"), do: "Test"
  def mail_label(_none), do: "Aucun"

  def date(nil), do: "—"
  def date(at), do: Calendar.strftime(at, "%d/%m/%Y")
end
