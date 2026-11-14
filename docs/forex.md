# Taux de change (forex)

Syli Atlas tient ses propres taux de change pour les 42 monnaies africaines,
l'euro et le yuan, face au dollar. Code : `SyliAtlas.Fx`, `lib/syli_atlas/fx/`.

## Sources

| Source | Rôle | Affichée | Conditions |
| --- | --- | --- | --- |
| [fawazahmed0/exchange-api](https://github.com/fawazahmed0/exchange-api) | Principale, chaque jour, historique par date | Oui, citée sous chaque taux | CC0 ; pas de clé ni de quota ; source d'origine non nommée, aucune garantie |
| [ExchangeRate-API](https://www.exchangerate-api.com/docs/free) (`open.er-api.com`) | Contrôle seulement | Jamais | Rediffusion interdite, crédit obligatoire là où les taux sont montrés : on ne les montre donc pas |
| Parités officielles (`SyliAtlas.Economy.Currencies`) | XOF, XAF, KMF, CVE, STN, LSL, NAD, SZL, DJF, ERN | Oui | Calculées depuis la monnaie d'ancrage, jamais reprises d'une source |

Les taux ne sortent pas par l'API publique (`/api/v1`), par choix.

Chaque requête vers la source principale passe par jsDelivr puis, en cas
d'échec, par le miroir Cloudflare (`{date}.currency-api.pages.dev`), comme
le demande le projet.

## Chaîne

1. `FxImportWorker` (cron `10 1 * * *` UTC, et au premier démarrage en
   production si aucun taux n'existe) : source principale (`latest`), source
   de contrôle, puis publication. Échec de la source principale = nouvelle
   tentative Oban (5 essais).
2. Chaque réponse est gardée brute (stockage R2 ou disque, reçu dans
   `market_raw_payloads`, jeu `fx`).
3. Les taux des monnaies suivies vont dans `fx_rates` : une ligne par monnaie,
   jour et source, en unités pour un dollar, décimal exact stocké en texte.
4. `FxBackfillWorker` remplit les jours manquants depuis le 2 mars 2024,
   premier jour publié par la source (une requête par jour), dès qu'il en
   manque dans les 30 derniers ou que l'historique ne remonte pas jusque-là.
   Le simulateur de placement convertit le début d'un placement au taux de
   son jour : sans taux ce jour-là (et hors parité fixe), il reste dans la
   monnaie de l'indice.
5. `SyliAtlas.Fx.publish!/0` écrit le document `market:fx_rates` (table
   `snapshots`) : taux du dernier jour, taux d'environ un an plus tôt,
   parités, contrôles. Les pages ne lisent que lui.

## Contrôles (affichés « à vérifier »)

- `gap` : écart de plus de 2 % avec la source de contrôle (monnaies non liées) ;
- `jump` : plus de 10 % face au dollar depuis la veille ;
- `year_move` : plus de 10 % face au dollar sur un an (vraie dévaluation ou erreur).

L'ancien dollar zimbabwéen (ZWL) n'est pas suivi : seul le ZiG (ZWG). Le
12 nov. 2026, ZWL valait 66 710 pour 1 $ chez la source principale et 26,5
chez la source de contrôle.

## Pages

- `/fr/monnaies` (`/en/currencies`, `/es/monedas`, `/pt/moedas`, et sous
  `/ar`, `/hi`, `/zh`) : tableau des 42 monnaies (défilant sur 10 lignes, en-tête
  fixe), base dollar / euro / yuan, filtre par régime, tri, convertisseur en
  GET (sans script). Les variantes avec paramètres sont `noindex`.
- Fiche pays, bloc « Monnaie » : 1 dollar, 1 euro, 1 yuan en monnaie locale,
  variation sur un an (« parité fixe » face à la monnaie d'ancrage).

## Sélecteur de devise (tout le site)

Menu « Devise » dans l'en-tête (`SyliAtlasWeb.CurrencyMenu`, `assets/js/ui/money.js`),
d'après la maquette « Sélecteur de devise ».

- Par défaut, la devise du pays du visiteur, comme pour la langue : les pages
  étant en cache pour tous, le script demande une fois par visite `/visitor`
  (pays lu dans l'en-tête `CF-IPCountry` de Cloudflare, réponse jamais en
  cache). Zone euro → EUR, États-Unis → USD, Chine → CNY, pays africain → sa
  monnaie, autre pays → dollar. Pays inconnu → montants tels que publiés.
- Un choix fait dans le menu est gardé sur l'appareil (`localStorage`,
  clé `sa.currency`, partagée avec les sélecteurs des pages budget) et
  remplace la détection. « Devises d'origine » affiche tout tel que publié.
- Les montants sont écrits par le serveur dans leur devise de publication,
  dans `<span class="money" data-money data-currency [data-year]>`
  (`SyliAtlasWeb.Money.amount/2`, `Format.money_value/4`,
  `MarketComponents.money_amount/3`, `WorldBankComponents.money_usd/3`).
  Le montant d'origine reste affiché en petit sous le montant converti.
- Un montant annuel (PIB, dette, commerce) est converti au **taux moyen de
  son année** (`Fx.year_averages/0`, au moins 20 jours de taux ; document
  `market:fx_rates`, clé `year_avg`), jamais au taux du jour ; sans taux pour
  l'année, il reste tel que publié. Une séance de bourse utilise le dernier
  taux. Taux, ratios et pourcentages ne sont jamais convertis.
- Les taux viennent avec la page (`<script type="application/json">`),
  aucune requête de taux, aucune API.
