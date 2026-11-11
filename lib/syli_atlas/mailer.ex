defmodule SyliAtlas.Mailer do
  @moduledoc """
  Sends the emails (Swoosh). The adapter is chosen at boot from the
  environment (config/runtime.exs):

    * **Resend** in production (`RESEND_API_KEY`), through its HTTP API
      (`SyliAtlas.Mailer.Resend`, with idempotency keys);
    * **SMTP** to Mailpit outside production (`SMTP_HOST`, port 1025), on
      Railway or locally (`docker compose up -d mailpit`);
    * **Local** in development (`/dev/mailbox`), the test adapter in tests;
    * none: nothing is sent, and sign-in by email says it is not open yet.
  """
  use Swoosh.Mailer, otp_app: :syli_atlas

  require Logger

  @doc "The service in use, for the boot log and the admin: \"resend\", \"smtp host:port\", \"local\" or \"none\"."
  def service do
    Application.get_env(:syli_atlas, :mail_adapter) ||
      case Application.get_env(:syli_atlas, __MODULE__)[:adapter] do
        Swoosh.Adapters.Test -> "test"
        Swoosh.Adapters.Local -> "local"
        _ -> "none"
      end
  end

  @doc "Says at boot where emails go; a release without any says it loudly."
  def log_service do
    case service() do
      "none" ->
        Logger.warning(
          "mail: no adapter configured, no email will be sent (set RESEND_API_KEY or SMTP_HOST)"
        )

      service ->
        Logger.info("mail: #{service}")
    end
  end
end
