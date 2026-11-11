defmodule SyliAtlas.MailerConfigTest do
  # Reads config/runtime.exs as a release would, with the environment set.
  use ExUnit.Case, async: false

  @vars ~w(MAILER_ADAPTER RESEND_API_KEY SMTP_HOST SMTP_PORT SMTP_USERNAME SMTP_PASSWORD SMTP_TLS MAIL_FROM FIRST_ADMIN_EMAIL)

  setup do
    saved = Map.new(@vars, &{&1, System.get_env(&1)})
    Enum.each(@vars, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(saved, fn
        {k, nil} -> System.delete_env(k)
        {k, v} -> System.put_env(k, v)
      end)
    end)
  end

  # Each read starts from a clean environment.
  defp read(env, vars) do
    Enum.each(@vars, &System.delete_env/1)
    System.put_env(vars)
    Config.Reader.read!("config/runtime.exs", env: env)
  end

  defp app(config), do: Keyword.get(config, :syli_atlas, [])

  test "RESEND_API_KEY selects our Resend adapter" do
    config =
      read(:dev, %{
        "RESEND_API_KEY" => "re_test",
        "MAIL_FROM" => "Syli Atlas <bonjour@syliatlas.com>"
      })

    mailer = app(config)[SyliAtlas.Mailer]
    assert mailer[:adapter] == SyliAtlas.Mailer.Resend
    assert mailer[:api_key] == "re_test"
    assert app(config)[:mail_adapter] == "resend"
    assert app(config)[:mail_from] == {"Syli Atlas", "bonjour@syliatlas.com"}
    assert app(config)[:mail_enabled]
  end

  test "SMTP_HOST selects SMTP to Mailpit: plain, no auth, port 1025" do
    mailer = app(read(:dev, %{"SMTP_HOST" => "mailpit.railway.internal"}))[SyliAtlas.Mailer]
    assert mailer[:adapter] == Swoosh.Adapters.SMTP
    assert mailer[:relay] == "mailpit.railway.internal"
    assert mailer[:port] == 1025
    assert mailer[:tls] == :never
    assert mailer[:auth] == :never

    mailer =
      app(
        read(:dev, %{
          "SMTP_HOST" => "smtp.example.com",
          "SMTP_PORT" => "587",
          "SMTP_TLS" => "always",
          "SMTP_USERNAME" => "u",
          "SMTP_PASSWORD" => "p"
        })
      )[SyliAtlas.Mailer]

    assert {mailer[:port], mailer[:tls], mailer[:auth], mailer[:username]} ==
             {587, :always, :always, "u"}
  end

  test "Resend wins over SMTP unless MAILER_ADAPTER says otherwise" do
    vars = %{"RESEND_API_KEY" => "re_test", "SMTP_HOST" => "mailpit"}
    assert app(read(:dev, vars))[SyliAtlas.Mailer][:adapter] == SyliAtlas.Mailer.Resend

    assert app(read(:dev, Map.put(vars, "MAILER_ADAPTER", "smtp")))[SyliAtlas.Mailer][:adapter] ==
             Swoosh.Adapters.SMTP
  end

  test "development falls back to the local mailbox; bad settings stop the boot" do
    assert app(read(:dev, %{}))[SyliAtlas.Mailer][:adapter] == Swoosh.Adapters.Local

    assert_raise RuntimeError, ~r/RESEND_API_KEY/, fn ->
      read(:dev, %{"MAILER_ADAPTER" => "resend"})
    end

    assert_raise RuntimeError, ~r/unknown MAILER_ADAPTER/, fn ->
      read(:dev, %{"MAILER_ADAPTER" => "postman"})
    end

    assert_raise RuntimeError, ~r/SMTP_TLS/, fn ->
      read(:dev, %{"SMTP_HOST" => "x", "SMTP_TLS" => "maybe"})
    end
  end
end
