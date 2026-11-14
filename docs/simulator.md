# Simulateur de placement

`/fr/bourses/simulateur` (`/en/stock-exchanges/simulator`, `/es|pt/…/simulador`) :
« si j'avais placé tel montant dans tel indice tel jour, combien aurais-je
aujourd'hui ? ». Variante B du canvas « Simulateur » : bandeau sombre, phrase
qui est un formulaire GET (chaque résultat a son adresse, partageable).

## Données

- Clôtures des indices : `market_index_values`. L'historique vient une fois de
  Mansa (`GET /indices/{code}/history`, `IndexHistoryWorker`, au démarrage en
  production), une requête par indice ; un indice qui a déjà trois ans de
  clôtures n'est pas redemandé. Les payloads sont gardés bruts et passent par
  le pipeline normal ; une séance déjà publiée n'est jamais remplacée par
  l'historique. Avant la première priorité de source (`@epoch`), les premières
  priorités connues s'appliquent.
- Un indice est proposé dès qu'il a trois ans et plus de 200 clôtures.
- Change : parités fixes exactes (`Economy.Currencies`), sinon nos taux
  stockés (`fx_rates`) du jour de début et de fin, à 7 jours près.

## Calcul (`SyliAtlas.Market.Simulator`)

Valeur finale, gain, rendement annuel moyen (au-delà d'un an), pire baisse
depuis un sommet, effet du change, année par année, même montant placé au
1er janvier des dix dernières années, courbe hebdomadaire.

## Ce que la page dit

Indice de prix : dividendes non compris ; frais, impôts, liquidité et taux de
la banque non comptés ; performances passées ; pas un conseil. Crédit
« Data by MansaAPI » : les clôtures sont montrées, jamais redistribuées (ni
téléchargement ni API).

## SEO

`WebApplication` + fil d'Ariane en JSON-LD, sitemap, `noindex` dès qu'un
réglage est dans l'adresse. Bouton « Simuler un placement » sur la page d'une
bourse qui a l'historique, entrée dans le menu Thèmes.
