defmodule SyliAtlasWeb.UnsubscribeHTML do
  use SyliAtlasWeb, :html

  alias SyliAtlasWeb.Paths

  embed_templates "unsubscribe_html/*"

  def what(nil), do: gettext("This link is no longer valid.")
  def what("alert"), do: gettext("Stop this alert")
  def what("digest"), do: gettext("Stop the digest of favourites")
  def what("all"), do: gettext("Stop every alert and the digest")

  def done("alert"), do: gettext("This alert is paused. You can resume it from your space.")
  def done("digest"), do: gettext("You will no longer receive the digest.")
  def done(_all), do: gettext("Your alerts are paused and the digest is off.")
end
