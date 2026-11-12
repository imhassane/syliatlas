# Export des données et intégration (iframe)

Deux façons de faire sortir les chiffres d'une fiche (pays, région, Afrique) :
les **télécharger** et les **intégrer** dans un autre site (journal, blog,
institution).

## Export : `SyliAtlasWeb.ExportController`

| Adresse | Format |
| --- | --- |
| `/fr/pays/cote-d-ivoire/donnees.csv?from=2020&to=2025` | CSV |
| `/fr/pays/cote-d-ivoire/donnees.xlsx` | Excel (onglet « Données » + onglet « À propos ») |
| `/fr/pays/cote-d-ivoire/donnees.json` | la réponse de l'API (`/api/v1/areas/CIV`) |
| `/fr/regions/afrique-de-l-ouest/donnees.csv`, `/en/regions/africa/data.xlsx` | régions et continent |

- **Fabriqué dans la requête, côté serveur**, à partir du document précalculé de
  la fiche (`Queries.area_profile/3`) : quelques kilo-octets, quelques
  millisecondes. **Pas d'Oban** : une file n'aurait de sens que pour un très gros
  fichier (toute l'Afrique, toutes les sources), à fabriquer une fois par édition
  dans `AfterPublishWorker`.
- Cache : pipeline `:public_cache` (ETag, 304), comme les pages.
- Contenu : les 11 indicateurs FMI de la fiche, une ligne par indicateur, une
  colonne par année, puis le statut de chaque année (observé, estimation,
  projection). Chaque fichier porte la source (attribution de l'API), l'édition,
  la licence des chiffres FMI, celle des calculs Syli Atlas (CC BY 4.0), la phrase
  à citer, l'adresse de la fiche et la date d'export.
- CSV : UTF-8 avec BOM ; point-virgule et virgule décimale en fr/es/pt (ce
  qu'attend Excel), virgule et point ailleurs ; `sep=comma|semicolon` force le choix.
- Excel : écrit sans dépendance (`SyliAtlasWeb.Export.Xlsx`, `:zip` d'Erlang),
  chiffres en nombres, première ligne en gras.
- **Jamais de cours de bourse** (licence MansaAPI : affichage seulement). Ils ne
  sont pas dans le document de la fiche ; le fichier dit qu'ils sont exclus.
- Notations : pas encore exportées (conditions des agences à vérifier).

Sur la fiche : bouton **Données** (menu `<details data-nav-menu>` : sans
JavaScript, Échap le ferme et rend le focus) avec les trois fichiers de la
période affichée, et lien **Intégrer**.

## Intégration : `SyliAtlasWeb.EmbedController`

- **Cadre** : `/embed/:locale/:kind/:slug/:view`, par exemple
  `/embed/fr/pays/cote-d-ivoire/inflation?from=2020&to=2025`. `view` = une clé
  d'indicateur (le graphique de la fiche, comparé à la région) ou `summary`
  (6 chiffres clés). Options : `compare=0`, `title=0`,
  `theme=light|dark` (défaut : réglage du lecteur), `edition`.
- **Page de configuration** : `/fr/pays/:slug/integrer` (`/en/countries/:slug/embed`),
  formulaire GET (marche sans JavaScript), aperçu, code à copier.
- **oEmbed** : `GET /oembed?url=<adresse d'une fiche ou d'un cadre>` (JSON, type
  `rich`) ; les fiches l'annoncent par `<link rel="alternate" type="application/json+oembed">`.
  Coller l'adresse d'une fiche dans WordPress ou Ghost suffit.
- **Hauteur** : `/embed-frame.js` (dans le cadre) envoie sa hauteur par
  `postMessage` ; `/embed.js` (chez le journal, facultatif) la pose sur
  l'`<iframe>` après avoir vérifié l'origine **et** le cadre émetteur.
- **Édition** : le code contient l'édition FMI du moment. Les documents des
  éditions passées ne sont pas gardés : le cadre affiche toujours la dernière
  édition et, si elle diffère, une ligne le dit (« Chiffres mis à jour depuis cet
  article »). Figer vraiment un article demanderait d'archiver les documents par édition.

### Sécurité (CSP)

- Le pipeline `:embed` (`SyliAtlasWeb.Plugs.Embed`) saute
  `put_secure_browser_headers` : pas de `frame-ancestors 'self'` imposé par
  Phoenix, pas de `X-Frame-Options`, pas de session ni de cookie.
- `SyliAtlasWeb.CSP.embed_policy/0` remplace la politique du site sur ces seules
  réponses : `frame-ancestors *`, `script-src 'self'` (aucun script en ligne : le
  seul script est `/embed-frame.js`), `form-action 'none'`, `frame-src 'none'`.
  Mode suivi de `CSP_MODE` comme le reste (report-only, enforce, off).
- Le reste du site garde `frame-ancestors 'self'` : une fiche ne peut pas être
  encadrée ailleurs (vérifié dans Chrome).
- À surveiller en production : que Cloudflare n'ajoute pas d'`X-Frame-Options`
  sur `/embed/*`.

### Accessibilité

- `<iframe title>` dans le code fourni ; dans le cadre : `lang`/`dir`, un `h1`
  (masqué visuellement avec `title=0`), le graphique en `role="img"` avec son
  tableau de valeurs, liens « nouvel onglet » annoncés.
- Aucune animation dans un cadre (une capture ou une impression ne doit jamais
  saisir une courbe à moitié tracée).
- Page de configuration : chaque contrôle étiqueté, langues nommées dans leur
  langue (`lang` sur chaque option), aide du champ de code reliée par
  `aria-describedby`, copie annoncée par une zone `role="status"` hors du bouton,
  cibles de 44 px.
- Vérifié le 12 nov. 2026 avec axe-core (WCAG 2.2 AA) dans Chrome : 0 violation
  sur 4 cadres (clair, sombre, arabe) et les 2 pages ; cadres affichés depuis une
  autre origine, hauteur ajustée.
