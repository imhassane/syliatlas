# The country recap without an account

Anyone can get a weekly (Mondays) or monthly (the 1st) email about the
African countries they choose, with an email address only: no account, no
password. It is separate from the **member digest** of favourites and
alerts (`SyliAtlas.Accounts.Digests`), which needs an account.

Code: `SyliAtlas.Recaps` (context), `SyliAtlas.Recaps.Subscription`
(schema), `SyliAtlas.Recaps.Content` (what a recap says),
`SyliAtlas.Recaps.Emails` (the two emails), `SyliAtlas.Workers.RecapWorker`
and `RecapEmailWorker` (Oban, queue `alerts`), `SyliAtlasWeb.RecapController`
(pages), `assets/js/ui/recap.js` (the footer dialog).

## What is stored

Table `recap_subscriptions`, one row per address:

| Column | What | Why |
|---|---|---|
| `email` | lower-cased, trimmed, unique | where to send |
| `countries` | ISO codes, 1 to 10, in the order picked | what to send |
| `frequency` | `weekly` or `monthly` | when to send |
| `locale` | `fr` or `en`, the language of the form | the language of every email |
| `confirmed_at` | when the confirmation link was used, or `NULL` | nothing but the confirmation email goes to an unconfirmed address |
| `last_sent_on` | the day of the last recap | a job run twice sends once |
| `inserted_at`, `updated_at` | timestamps | the purge of unconfirmed addresses |

Nothing else: no name, no IP address (the visitor's address is used in
memory for the rate limit, never written), no tracking of opens or clicks.
The emails go out through the configured mailer (Resend in production,
Mailpit in development, see `README.md`).

## How long

- **Unconfirmed**: deleted 7 days after the last request
  (`Recaps.purge_unconfirmed/1`, every morning before the recaps are sent).
- **Confirmed**: kept until the person stops the recap. Stopping deletes
  the row at once (`Recaps.unsubscribe/1`); nothing is kept « for the
  record ».
- Backups: none of the database today besides the Railway volume. When
  backups come (Litestream to R2 is planned), a deleted row will remain in
  them until their old generations expire: say so here.

The page `/fr/recap` says this under « Ce que nous gardons ».

## The life of a subscription

1. **Request** — `POST /fr/recap` (or `/en/recap`), from the recap page or
   the footer dialog (JSON). `Recaps.subscribe/2`:
   - validates the address and the choices (1 to 10 known countries);
   - limits confirmation emails to 3 per address and 20 per visitor
     address per hour (`SyliAtlasWeb.RateLimit`, in memory);
   - stores a new address unconfirmed; updates the choices of an
     unconfirmed one; **leaves a confirmed one untouched**;
   - sends the confirmation email. Its link carries the choices, signed
     (`Phoenix.Token`, salt `recap-confirm`, 7 days): they apply only when
     the link is used, so nobody can change the countries of an address
     they do not read.
   - The answer is the same whether the address was known or not, so the
     form does not reveal who is subscribed.
2. **Confirmation** — `GET /recap/confirm/:token` shows the choices and a
   button; `POST` applies them (`Recaps.confirm/1`). GET never acts, since
   mail scanners open links.
3. **Sending** — cron `45 6 * * *` (UTC): `RecapWorker` purges, then
   enqueues one `RecapEmailWorker` per confirmed address due today
   (`Recaps.due_ids/1`; Mondays, the 1st for monthly). Unique job per
   address and day; Resend idempotency key `recap-<id>-<date>`.
4. **Change** — `GET/POST /recap/manage/:token` (salt `recap-manage`, 400
   days): countries and frequency.
5. **Stop** — `GET /recap/stop/:token` asks, `POST` deletes the row. The
   recap carries `List-Unsubscribe` and `List-Unsubscribe-Post` (RFC 8058):
   mail clients' one-click POST works without a CSRF token, the signed
   token is the proof. A second click still says « stopped ».

The pages under `/recap` and `/fr/recap` have no session and no CSRF token:
the form sits in the footer of cached public pages. A forged request can
only make Syli Atlas send a confirmation email, bounded by the rate limits.

## What a recap says

For the period (the past week, or the past month), `Recaps.Content.build/4`:

- **Summary**: number of rating decisions and the countries concerned,
  exchanges up and down, whether a new IMF edition was published.
- **Per country**, those with a rating decision first:
  - the rating decisions of the period, or the current rating of each
    agency;
  - the main index of the country's exchange (BRVM for the WAEMU
    countries, BVMAC for CEMAC…): its change from the last close before
    the period to the last close in it. Left out when the market figures
    may not be shown (`Market.public?/0`) or when the quality checks flag
    the index (missing, stale, suspect change);
  - the currency: the fixed peg (CFA francs: 1 EUR = 655.957) or the
    latest dollar rate from the market source. Only the latest rate is
    stored, so there is no weekly change of the currency yet;
  - growth, inflation and public debt for the current year, from the
    published IMF edition, with its status (estimate or projection).
- **Sources and credits**: IMF edition, rating agencies, and « Data by
  MansaAPI » with its link when market figures appear; « closing prices,
  not real time » and « information, not investment advice ».

## Licence of the market figures

MansaAPI's licence (https://mansaapi.com/licensing, read on 11 November
2026) allows displaying its data in our own product on every tier, with the
visible credit « Data by MansaAPI » linked to mansaapi.com on the free
tier, and forbids redistribution (« providing Mansa API data onward as
data ») below the Institutional tier. The page does not mention emails.
Decision of 11 November 2026 (Thierno): the recap shows the closing index
and the exchange rate, with the credit and the link, as display in our
product. Keep a written confirmation from MansaAPI (hello@mansaapi.com)
with the project records. If it were refused, remove the market and
currency rows in `Recaps.Content` (`market/5`, `currency/3`); the peg of
the CFA francs is not MansaAPI data and can stay.

## Development

- `mix test test/syli_atlas/recaps_test.exs test/syli_atlas_web/controllers/recap_controller_test.exs`
- With `mix phx.server`, emails land in `/dev/mailbox`; the link of the
  confirmation email works locally.
- To send a recap at once: `SyliAtlas.Recaps.send(id, ~D[2026-11-23])` (a
  Monday) in `iex -S mix`.
