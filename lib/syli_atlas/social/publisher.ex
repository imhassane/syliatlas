defmodule SyliAtlas.Social.Publisher do
  @moduledoc """
  Where approved posts go. Chosen at boot (config/runtime.exs):
  `SyliAtlas.Social.Buffer` when `BUFFER_API_KEY` is set (production),
  else `SyliAtlas.Social.Simulated` (development, Railway's dev environment,
  tests): nothing leaves the server.
  """

  @type network :: :x | :linkedin
  @type post :: %{
          required(:text) => String.t(),
          optional(:image_url) => String.t() | nil
        }

  @typedoc "`:queue` (next free slot of the schedule) or `:now` (at once)."
  @type mode :: :queue | :now

  @typedoc """
  What the service says of one post: `status` "scheduled", "sending",
  "sent", "error" or "draft"; `due_at`, `sent_at` (UTC); `error`;
  `metrics` (%{"impressions" => 12, …}, sent posts only).
  """
  @type remote :: %{
          status: String.t(),
          due_at: DateTime.t() | nil,
          sent_at: DateTime.t() | nil,
          error: String.t() | nil,
          metrics: map()
        }

  @typedoc """
  The posting schedule: `timezone` and, per day ("mon"…"sun"), the slots
  as "HH:MM" (a paused day has none).
  """
  @type schedule :: %{timezone: String.t(), days: %{String.t() => [String.t()]}}

  @doc "The connected accounts: `%{id, name, service}`."
  @callback channels() :: {:ok, [map()]} | {:error, String.t()}

  @doc "Adds one post to the network's queue (or posts it now); returns the service's id."
  @callback publish(network(), post(), mode()) :: {:ok, String.t()} | {:error, String.t()}

  @doc "The state of posts sent to the service, by id (unknown ids are left out)."
  @callback posts([String.t()]) :: {:ok, %{String.t() => remote()}} | {:error, String.t()}

  @doc "Takes a post out of the service's queue (« Retirer »)."
  @callback delete(String.t()) :: :ok | {:error, String.t()}

  @doc "The posting schedule of the network's account."
  @callback schedule(network()) :: {:ok, schedule()} | {:error, String.t()}

  def adapter,
    do:
      Application.get_env(:syli_atlas, SyliAtlas.Social, [])[:adapter] ||
        SyliAtlas.Social.Simulated

  def simulated?, do: adapter() == SyliAtlas.Social.Simulated

  @doc "Buffer's slots as set on 17 Nov. 2026, used while the service cannot be read."
  def default_schedule do
    weekday = ~w(10:00 14:00 19:00)

    %{
      timezone: "Europe/Paris",
      days: %{
        "mon" => weekday,
        "tue" => weekday,
        "wed" => weekday,
        "thu" => weekday,
        "fri" => weekday,
        "sat" => [],
        "sun" => []
      }
    }
  end
end
