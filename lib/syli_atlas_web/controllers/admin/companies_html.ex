defmodule SyliAtlasWeb.Admin.CompaniesHTML do
  use SyliAtlasWeb, :html

  import SyliAtlasWeb.AdminComponents, only: [admin_shell: 1]

  embed_templates "companies_html/*"

  def status_label("pending"), do: "À vérifier"
  def status_label("published"), do: "Affichée"
  def status_label("hidden"), do: "Masquée"
  def status_label("withdrawn"), do: "Retirée"

  def status_class("published"), do: "pill-ok"
  def status_class("hidden"), do: "pill-warn"
  def status_class(_), do: "pill-neutral"

  def product_name(id),
    do:
      Gettext.with_locale(SyliAtlasWeb.Gettext, "fr", fn ->
        SyliAtlasWeb.TradeTopics.product_name(id)
      end)

  def kind_name(kind),
    do:
      Gettext.with_locale(SyliAtlasWeb.Gettext, "fr", fn ->
        SyliAtlasWeb.CompanyComponents.kind_label(kind)
      end)

  def when_text(nil), do: "jamais"
  def when_text(dt), do: Calendar.strftime(dt, "%d/%m/%Y %H h %M")
end
