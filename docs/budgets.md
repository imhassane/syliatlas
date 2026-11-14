# Budgets et lois de finances

Code : `SyliAtlas.Budgets`, `lib/syli_atlas/budgets/`. Pages : `/fr/budgets`
(toutes langues) et l'onglet « Budget de l'État » de chaque fiche pays
(`/fr/pays/mali/budget`). Admin : `/admin/budgets`.

## Ce que chaque pays a dès le départ (lot 1)

- **Recettes et dépenses des administrations publiques, % du PIB** : FMI,
  Fiscal Monitor (séries DataMapper `GGR_G01_GDP_PT`, `G_X_G01_GDP_PT`).
  Fichier livré `priv/data/imf_fiscal_monitor.json`, mis à jour par
  `mix budgets.refresh_imf`. C'est le modèle du FMI, pas la loi votée : la
  page le dit (« Estimation FMI »).
- **Qui vote le budget et où paraissent les lois** : `priv/data/budget_catalog.json`
  (54 pays), copié dans `budget_profiles` au démarrage. Une fiche modifiée dans
  l'admin n'est plus écrasée par le fichier. Seuls les liens cochés « vérifiés »
  s'affichent sur le site.

## Les lois de finances (lot 2)

1. Un fichier arrive : déposé dans l'admin (PDF jusqu'à 25 Mo) ou lu sur une
   page suivie (mode « page suivie » d'une fiche pays : `BudgetFetchWorker`,
   cron `30 5 * * *` UTC, liens PDF ou motif choisi, 5 nouveaux fichiers au plus
   par passage). Il est gardé brut (R2, `market_raw_payloads`, jeu `budget`) ;
   le même fichier n'est jamais relu pour un pays.
2. `BudgetExtractWorker` l'envoie à Claude (`SyliAtlas.Budgets.Extractor`,
   clé `ANTHROPIC_API_KEY`, modèle `claude-sonnet-5-5` ou
   `BUDGET_EXTRACT_MODEL`) : exercice, type, étape, dates, totaux, page de
   chaque chiffre. Une lecture par fichier et par modèle (« Relire » dans
   l'admin en force une nouvelle). Sans clé : le fichier attend, la loi se
   saisit à la main.
3. Contrôles automatiques (`SyliAtlas.Budgets.Checks`) : devise du pays,
   montants positifs, dates dans l'ordre, ×10 ou −90 % face à la loi précédente
   (« 000 » perdu), variation de plus de 40 %, dépenses hors 2–80 % du PIB.
4. Validation humaine avec le lien https du texte officiel ; dans la même
   transaction, `BudgetPublishWorker` (file `budgets`) reconstruit les documents
   `budget:overview` et `budget:country:<code>` puis lance les alertes
   « loi de finances » des membres qui suivent le pays.

Niveau affiché : « Loi de finances officielle » dès qu'une loi initiale ou
rectificative de l'année ou de l'année précédente est en ligne, sinon
« Estimation FMI ».

## Montants

Écrits côté serveur dans la devise par défaut de la langue (euro en français,
dollar ailleurs), le montant local dessous. `assets/js/ui/money.js` les réécrit
dans la devise choisie par le lecteur (gardée dans le navigateur), avec les
taux du document `market:fx_rates` embarqués dans la page : les pages restent
en cache.

## Propositions issues de la recherche web

`priv/data/budget_research.json` contient les lois de finances 2026 (ou 2026/27)
trouvées par recherche web pour 53 pays (l'Érythrée ne publie pas de budget) :
référence, dates, recettes, dépenses, devise, lien source et une note sur la
fiabilité de chaque chiffre. Au déploiement, `Budgets.seed_research!/0` en fait
des propositions **en attente** (origine `research`), visibles dans
`/admin/budgets`. Rien n'est publié sans validation. Le seed est idempotent :
une loi déjà proposée ou publiée (même pays, exercice, type et numéro), y compris
une proposition rejetée, n'est pas recréée.

Les montants marqués « approximatif », « converti » ou « supplémentaire » dans la
note doivent être corrigés avant validation, de préférence en déposant le texte
officiel pour que l'IA en lise les articles d'équilibre.
