# Skill : Creer un article evergreen SEO (full auto) — Journal Marketing

Cette skill produit **automatiquement** un article evergreen SEO, bilingue FR + EN, a partir d'un mot-cle pris dans `roadmap.yaml`. Aucun input humain, aucun point d'arret, publication directe sur GitHub.

Elle est declenchee par une routine cloud planifiee (cron `0 1 * * 1-5`, du lundi au vendredi a 1h UTC, soit 5 articles par semaine). Elle peut aussi etre lancee manuellement pour tester.

Ce blog est **Journal Marketing** (journal-marketing.fr), media debrande sur le marketing digital. Deux differences majeures avec la version reseau de cette skill :
1. **L'analyse passe par l'API Datafer** (source nominale depuis le 2026-09-01), avec CrazySERP puis WebSearch en repli. Pas par SerpAPI, pas par un MCP. Le prompt de la routine de ce blog vit sur le compte Claude Team Froggies (Theo) et **porte les 4 cles depuis le 2026-09-07** : les runs sortent donc en mode `datafer`, avec le controle de score de l'etape 7bis.
2. **Le contenu vit sous `content/fr/` et `content/en/`**, pas `content/blog/`.

## Quand l'utiliser

- Declenchement automatique via la routine cloud.
- Declenchement manuel : `/create-article-auto` depuis la racine du repo `journal-marketing`.

## Pre-requis dans le blog

- `roadmap.yaml` a la racine, avec au moins une entree `status: todo`.
- `hugo.toml` configure FR (racine) + EN (`/en/`).
- `data/authors.yaml` present (8 personas).
- `content/fr/blog/` et `content/en/blog/` existent.
- `.claude/scripts/fetch-image.sh` present.
- Remote git `origin` configure, acces push sur `main`.

## Philosophie : full auto, pas de human in the loop

Aucune question a l'utilisateur. Toutes les decisions sont prises par l'agent a partir de :
- le mot-cle et la categorie de la roadmap,
- l'analyse SERP CrazySERP (ou le repli, voir Etape 1),
- le contexte du site (`CLAUDE.md` du blog, `data/authors.yaml`, `hugo.toml`),
- les articles deja publies (scan de `content/fr/blog/`).

Si une etape bloque (image introuvable, build Hugo casse, push rejete apres rebase), l'agent **n'insiste pas** : il passe l'entree en `status: failed` avec le message d'erreur, commit le roadmap seul, et sort en code non-zero.

**Exceptions qui ne sont JAMAIS un motif d'echec** : l'indisponibilite de CrazySERP (Etape 1) et l'echec de la recuperation d'une photo (Etape 5). Dans les deux cas on continue et on publie. Attention a la nuance cote image : ne pas faire echouer le run ne veut **pas** dire publier sans visuel, l'article recoit alors le visuel de charte genere (Etape 5). Un article sans champ `image` est un defaut, pas un repli acceptable.

## Regles editoriales non negociables de ce blog

Elles priment sur toute habitude generique. Les agents rediger ont deja derape dessus par le passe.

- **Debranding strict** : le site publie ne mentionne JAMAIS datashake. Ni le nom, ni un lien `datashake.fr`, ni un CTA agence, ni une allusion a une agence "nous". Cette skill ne produit **jamais** de classement d'agences : uniquement de l'evergreen informationnel.
- **Jamais de tiret cadratin (—) ni demi-cadratin (–)**, nulle part : titre, meta, body, alt, FAQ. Utiliser virgule, point, deux-points, ou reformuler.
- **Jamais de point median (·)** dans un texte visible.
- **Accents obligatoires** partout dans le contenu FR (é, à, è, ù, ç).
- **Pas de tutoiement**, pas de "je / tu / nous / vous". Ton impersonnel.
- **Pas de separateur horizontal** (`---`) dans le body.
- **Pas de `&`** dans les H2 et H3.
- Pas de chiffre invente. Si une donnee n'est pas sourcee par la SERP, ne pas la citer. Les agents de ce blog ont deja produit des ratios fabriques.

## Etape 0 — Selection de l'entree roadmap

1. Se placer a la racine du repo.
2. `git pull --rebase origin main`. Si echec : abort avec log clair.
3. Lire `roadmap.yaml`.
4. Filtrer : `status == todo` **ET** `scheduled_date <= today` (YYYY-MM-DD).
5. Trier par `scheduled_date` croissante, prendre la premiere.
6. Si aucune entree eligible : loguer "Aucune entree roadmap eligible aujourd'hui" et **exit 0**. Ne jamais avancer une entree future.

L'entree fournit : `kw`, `category`, `scheduled_date`.

La `category` doit etre l'une des 7 rubriques du blog. Ne jamais en inventer une :

| Categorie FR (roadmap et frontmatter FR) | Categorie EN (frontmatter EN) |
|---|---|
| SEO | SEO |
| IA et GEO | AI and GEO |
| Contenu | Content |
| Social et influence | Social and influence |
| Publicité en ligne | Online advertising |
| Data et mesure | Data and measurement |
| Outils et comparatifs | Tools and comparisons |

## Etape 1 — Analyse semantique via Datafer (repli CrazySERP puis WebSearch)

L'analyse du paysage concurrentiel passe par l'**API Datafer**, l'outil semantique interne de datashake. Un brief Datafer donne ce que l'appel SERP seul ne donnait pas : les **structures Hn completes du top 10**, le **contenu redige** de chaque concurrent, les **termes NLP ponderes** avec leur taux de presence, les **clusters semantiques**, les **sections recurrentes de la SERP**, les **entites nommees**, le **nombre de mots cible** calcule sur les concurrents reels, les **PAA**, et un **score /100** qui permet de mesurer l'article produit avant de le publier.

**Datafer est la source nominale depuis le 2026-09-01.** CrazySERP reste branche pour deux usages precis : le **check AI Overview** (Datafer ne l'expose pas) et le **repli** si Datafer echoue.

Les deux cles sont fournies dans le prompt de la routine (`DATAFER_API_KEY` et `CRAZYSERP_API_KEY`) et **ne doivent jamais etre ecrites dans le repo** : les repos du reseau sont publics. Si le prompt n'en fournit qu'une, la cascade de repli (1.5) s'adapte toute seule et l'article sort quand meme.

### 1.1 Verifier la cle, puis creer le brief Datafer

**Premier reflexe : la cle est-elle la ?**

```bash
if [ -z "$DATAFER_API_KEY" ]; then
  echo "DATAFER_API_KEY absente, mode crazyserp"   # voir 1.5, cas 0
fi
```

Si elle est absente ou vide, **ne pas tenter Datafer du tout** : passer directement au mode `crazyserp` (1.5, cas 0). Ce n'est jamais un motif d'echec. **Au 2026-09-07, les 14 routines du parc portent toutes la cle** : si un run tombe malgre tout dans ce cas 0, ce n'est plus une situation normale mais le signe que son prompt a ete modifie ou restaure depuis, a signaler.

```bash
export BASE="https://datafer.analytics-e0d.workers.dev"
curl -s -w '\nHTTP=%{http_code}\n' --max-time 120 -X POST "$BASE/api/v1/briefs" \
  -H "Authorization: Bearer $DATAFER_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"keyword":"<kw>","country":"fr"}'
```

Recuperer le champ `.id` de la reponse. `jq` n'est pas toujours present dans le sandbox : faire l'extraction en `python3` en cas d'absence.

**Ne JAMAIS appeler Datafer avec `urllib` de Python.** Cloudflare rejette la signature `Python-urllib` en **403 `error code: 1010`**, et ce n'est ni la cle ni l'egress. Tout passe par `curl` (mesure du 2026-09-01 : le meme appel echoue en urllib et repond 200 en curl).

### 1.2 Poller jusqu'a `ready`

```bash
for i in $(seq 1 48); do
  STATUS=$(curl -s --max-time 30 "$BASE/api/v1/briefs/$ID" \
    -H "Authorization: Bearer $DATAFER_API_KEY" \
    | python3 -c 'import json,sys;print(json.load(sys.stdin).get("status",""))')
  [ "$STATUS" = "ready" ] && break
  [ "$STATUS" = "failed" ] && break
  sleep 5
done
```

- **Timeout 240 s, pas 90 s.** Mesures du 2026-09-01 : 31 s depuis le sandbox cloud, 89 s depuis un Mac sur un mot-cle jamais analyse. La doc annonce 20 a 60 s, c'est optimiste.
- Les endpoints v2 renvoient **409** tant que le brief est `pending` : ne jamais les appeler avant `ready`.
- `status: failed` cote Datafer signifie que son analyse SERP initiale a echoue : basculer sur le repli (1.5) sans insister.

### 1.3 Rapatrier les 4 endpoints v2

Une fois `ready`, quatre appels, tous sous la seconde (mesure du 2026-09-01) :

```bash
for EP in "" "/competitors" "/nlp" "/paa"; do
  curl -s --max-time 60 "$BASE/api/v2/briefs/$ID$EP" \
    -H "Authorization: Bearer $DATAFER_API_KEY" \
    -o "/tmp/datafer$(echo "$EP" | tr -d '/' | sed 's/^$/brief/').json"
done
```

Ce qu'on garde de chacun :

| Endpoint | Ce qu'on en tire | Sert a |
|---|---|---|
| `/api/v2/briefs/{id}` | `intent`, `targetWordCount`, `minWordCount`, `maxWordCount`, `avgHeadings`, `avgParagraphs`, `competitors.avg`, `competitors.best` | longueur cible (etape 7), nombre de Hn (etape 3), barre a battre (etape 8bis) |
| `/competitors` | par concurrent : `position`, `title`, `link`, `wordCount`, `headings`, `h1`, `h2`, `h3`, `outline`, `score`, `hasContent` | structure Hn (etape 3), angles reellement traites |
| `/nlp` | `nlpTerms`, `semanticClusters`, `sections`, `entities`, `opportunities`, `stats` | couverture semantique (etape 7), regroupement des H2, differenciation |
| `/paa` | `paa` (question, snippet) | FAQ (etape 3 et 7) |

**Formes reelles a connaitre, la doc `doc-datafer-api` etait fausse sur deux champs** (verifie le 2026-09-01) :

- `sections` : `{label, hits, total, sampleHeadings, keyTerms}` et **pas** `{title, frequency}`. `hits` sur `total` est le nombre de concurrents qui traitent ce sujet, c'est le signal le plus utile de tout le brief.
- `entities` : `{label, hits, total, totalOccurrences}` et **pas** `{name, type, frequency}`.
- `opportunities` peut etre une **liste vide**, c'est frequent. Ne jamais faire dependre une etape de sa presence.
- `sections` et `entities` varient enormement d'un mot-cle a l'autre (mesure : 12 sections et 10 entites sur un mot-cle SIRH, 1 section et 2 entites sur un mot-cle mode). Un compteur bas n'est pas une panne, c'est une SERP pauvre : continuer avec ce qu'il y a.
- `volume` (issu de Haloscan) est souvent absent ou absurde (9 sur un mot-cle a fort trafic). **Purement informatif, il ne conditionne rien.**

### 1.4 Check AI Overview via CrazySERP (1 credit, non bloquant)

Datafer n'expose pas l'AI Overview. Un appel CrazySERP la donne, et c'est une regle transverse datashake sur tout brief et toute redaction.

```bash
curl -s --max-time 240 -G "https://crazyserp.com/api/search" \
  --data-urlencode "q=<kw>" \
  --data-urlencode "gl=fr" \
  --data-urlencode "hl=fr" \
  --data-urlencode "location=France" \
  --data-urlencode "page=1" \
  -H "Authorization: Bearer $CRAZYSERP_API_KEY" \
  -o /tmp/serp.json
```

- Lire `stats.has_ai_overview` **en priorite**, avec repli sur `parsed_data.has_ai_overview` : le champ existe aux deux endroits, et le lire seulement dans `parsed_data` a deja renvoye `None` a tort.
- Si `true`, lire `parsed_data.ai_overview.content` : les sous-questions traitees indiquent ce que Google considere comme le noyau du sujet, les couvrir explicitement dans la structure Hn. **Ne jamais recopier le texte de l'AIO.**
- Noter dans le log `AIO : Declenchee` ou `AIO : Non declenchee`.
- **Cet appel n'est jamais bloquant.** S'il echoue, noter `AIO : non verifiee` et continuer. La reponse sert aussi de repli SERP gratuit si Datafer est tombe (1.5).
- `--max-time 240` est obligatoire, `location=France` et rien d'autre (`Paris,France` resout silencieusement vers `Paris,Ontario,Canada`), pas de `tbm` (0 resultat et 1 credit debite quand meme).

### 1.5 Repli en cascade (ne jamais echouer sur cette etape)

**Datafer et CrazySERP sont tous les deux verifies fonctionnels depuis l'environnement cloud du reseau** (mesure du 2026-09-01 depuis `env_01WaB3uJJef85yE35Ha5rLdN` : Datafer creation 200 en 2,7 s, `ready` en 31 s, les 4 endpoints v2 en 200 ; CrazySERP 200 en 2,7 s, AIO detectee, 1 credit).

Bascule **des le premier echec, sans insister ni retenter** :

0. **`DATAFER_API_KEY` absente ou vide** : ne pas appeler Datafer, passer directement en mode `crazyserp` et loguer `DATAFER_API_KEY absente, mode crazyserp`. **Cas a connaitre** : les routines du parc mises en pause portent encore un prompt CrazySERP seul, donc une routine simplement reactivee par `{"enabled": true}` tourne sans cle Datafer. Le run publie quand meme, proprement, en mode degrade d'un cran. Pour recuperer le mode `datafer`, il faut patcher son prompt, ce que fait la skill `geo-pbn-routine-setup`.
1. **Datafer repond** : cas nominal, mode `datafer`.
2. **Datafer en erreur** (creation non-200, `status: failed`, timeout de polling, 409 persistant) : passer en mode `crazyserp` et travailler sur l'appel de 1.4, qui est deja fait. On perd les structures Hn concurrentes, les termes NLP et le nombre de mots cible ; on garde organiques, PAA, recherches associees et AIO. Loguer `DATAFER indisponible, repli crazyserp` et le signaler dans le message de commit.
3. **Datafer et CrazySERP tous les deux injoignables** : mode `websearch`, 3 recherches maximum sur le `kw`, titres et snippets uniquement.
4. **WebSearch aussi indisponible** : mode `degrade`, analyse a partir du seul `kw`, de la `category` et du contexte editorial du `CLAUDE.md`. **Publier quand meme.**

Cas particuliers a loguer explicitement, sans changer de mode :
- CrazySERP **402** (credits epuises) : loguer `CRAZYSERP 402 credits epuises`, l'AIO passe en `non verifiee`, Datafer continue normalement.
- Datafer **401** : cle revoquee, loguer `DATAFER 401 cle invalide` et passer en repli.
- Datafer **403 `error code: 1010`** : c'est un appel parti en urllib, pas une panne. Refaire en curl.

**L'indisponibilite des sources n'est JAMAIS un motif d'echec de la skill.** Noter dans le log et dans la ligne ajoutee a `MEMORY.md` le mode reellement utilise : `datafer`, `crazyserp`, `websearch` ou `degrade`.

### 1.6 Ne pas ouvrir les pages concurrentes

Ne **PAS** utiliser `WebFetch` sur les URLs concurrentes : dans le sandbox cloud les domaines commerciaux sont bloques par la politique reseau (403/503). **C'est desormais inutile** : Datafer a deja crawle le top 10 et rend le contenu par `/competitors/{n}` (champs `text` et `structuredHtml`) pour les concurrents dont `hasContent` est `true`. Appeler cet endpoint sur les 2 ou 3 meilleurs scores quand la structure demande a etre precisee, jamais sur les 10.

En repli `crazyserp`, `websearch` ou `degrade`, l'analyse se fait uniquement sur les titres, descriptions, PAA et AI Overview.

### 1.7 Synthese auto (aucun output humain, juste des variables internes)

L'agent determine :

- **Intention de recherche** : `intent` du brief Datafer (`informational`, `commercial`, `transactional`, `navigational`). En repli, inferee du pattern recurrent des titres du top 10.
- **Sujets a couvrir obligatoirement** : les `sections` dont `hits / total >= 0,5`, c'est-a-dire les sujets traites par au moins la moitie du top 10. `sampleHeadings` donne la formulation reelle des concurrents, a reformuler et jamais a recopier.
- **Angles de differenciation** : les `opportunities` (questions PAA peu couvertes) si la liste n'est pas vide, plus les `sections` a `hits` faible qui restent pertinentes pour le sujet, plus l'angle editorial propre au blog.
- **Champ semantique** : les `nlpTerms` tries par `score` decroissant. Retenir ceux dont `presence >= 50` (present chez au moins la moitie des concurrents). **Nettoyer la liste** : les `nlpTerms` remontent regulierement des noms de marques concurrentes et du bruit de listing (mesure du 2026-09-01 : `jouroff` en 8e position sur un mot-cle SIRH). Ne jamais placer une marque concurrente dans un Hn.
- **Termes a placer dans les Hn** : ceux dont `inHeadings` est `true`, ce sont ceux que les concurrents mettent eux-memes en titre.
- **Regroupement des H2** : les `semanticClusters` (`label` + `terms`) donnent des familles de sujets pretes a devenir des H2.
- **Entites a mentionner** : les `entities` a `hits` eleve, en excluant les marques concurrentes directes du blog.
- **FAQ pertinente ?** : construire 4 a 6 questions a partir des `paa`, **toujours reformulees**, jamais copiees mot pour mot. Completer avec les `opportunities` si besoin. S'il y a moins de 4 PAA, completer avec les `related` de l'appel CrazySERP transformees en questions. En repli `websearch` ou `degrade`, juger selon la nature du sujet.
- **Longueur cible** : `targetWordCount` du brief, borne par `minWordCount` et `maxWordCount`. Detail et garde-fous a l'etape 7.
- **Nombre de Hn cible** : `avgHeadings` du brief, borne entre 6 et 14.
- **Tableau pertinent ?** : vrai si le `kw` ou les titres du top contiennent "meilleur", "top", "vs", "ou", "comparatif", "prix", "tarif", ou si `intent` vaut `commercial`. Faux sinon.
- **Barre de score a battre** : `competitors.avg` et `competitors.best` du brief. Sert a l'etape 8bis.
- **Volume de recherche** : informatif, ne change pas la decision de publier.
- **AI Overview** : voir 1.4.

## Etape 2 — Title et meta description

Regles appliquees directement, pas d'appel a une autre skill. Une seule option, choix direct.

### Title
- Contient le `kw` dans le premier tiers.
- Maximum 60 caracteres (proxy sur les 580 px de la SERP).
- Le `title` du frontmatter ne contient **pas** le nom du site : Hugo l'ajoute deja dans la balise `<title>`.
- **Le budget de 60 caracteres porte donc sur le title RENDU**, frontmatter plus suffixe. `hugo.toml` declare `Journal Marketing` pour les deux langues, soit un suffixe ` | Journal Marketing` de **20 caracteres** : le frontmatter ne doit pas depasser **40 caracteres**. Controle : `python3 -c "print(len('<title frontmatter>') + 20)"` doit donner 60 au maximum. Si ca depasse, raccourcir l'angle, jamais le `kw`.
- Pas de cadratin. Deux-points autorises.

### Meta description
- Maximum 155 caracteres.
- Contient le `kw`.
- Une phrase descriptive factuelle. Pas de call to action, pas de teasing.

## Etape 3 — Structure Hn

- **Pas de H1 dans le body.** Hugo genere le H1 a partir du `title`.
- 4 a 7 H2 batis sur les patterns identifies en 1.5. Priorite aux sujets presents chez 3 concurrents et plus, puis 2 et plus, puis les angles uniques a fort potentiel.
- 1 a 2 H2 d'angle propre au blog (positionnement lu dans `CLAUDE.md`).
- Si l'AIO est declenchee : au moins un H2 repond frontalement a la question centrale traitee par l'AIO, en 2 a 3 phrases denses placees juste sous le H2. C'est ce format qui se fait citer.
- Dernier H2 : "Questions frequentes", en accordeons `<details><summary>`.
- H3 : 1 a 3 par H2, optionnels.
- H2 explicites et auto-suffisants, lisibles hors contexte. Pas de "Introduction" ni "Conclusion" bruts.

## Etape 4 — Selection de l'auteur

1. Lire `data/authors.yaml` (8 personas).
2. Scorer chaque auteur sur les recoupements entre ses `topics` / `expertise` et le couple `kw` + `category`.
3. Prendre le meilleur score.
4. Egalite ou score nul : `la-redaction`.

Le meme identifiant sert en FR et en EN (les champs `role` et `bio` sont deja bilingues dans `authors.yaml`).

**Ce blog a deux champs auteur, les deux sont obligatoires** :
```yaml
author: "thomas-durand"
auteurs: ["thomas-durand"]
```
`author` sert a l'affichage, `auteurs` alimente la taxonomie des pages auteur. En oublier un casse silencieusement une des deux.

## Etape 5 — Image hero

```bash
bash .claude/scripts/fetch-image.sh "<kw traduit en anglais>" "<slug-fr>" "static/images/blog"
```

- Query en anglais : les trois banques sont majoritairement indexees en anglais.
- Sortie du script sur 3 lignes : chemin Hugo, alt suggere, credit.
- **Cascade de sources depuis le 2026-09-04** : `Pexels` -> `Unsplash` -> `Openverse` ->
  visuel de charte genere. Le script descend d'un palier a chaque echec, sans jamais
  rendre la main sans visuel.
- **Openverse est passe en dernier recours, il n'est plus la source nominale.** Mesure du
  2026-09-04 sur les 45 heros du blog : 5 degrades generes, 10 photos franchement hors
  sujet (salle de controle de bus pour Looker Studio, conseil d'administration pour la
  ligne editoriale, ecran gov.uk pour le web analytics, tablette affichant 2017 pour le
  calendrier editorial) et 15 photos generiques interchangeables, pour seulement 15 photos
  reellement pertinentes. Il federe Flickr et Wikimedia, donc des archives et des photos
  perso : le filtre de licence ne dit rien de la pertinence. Il **sert aussi des URLs
  mortes** (lien Wikimedia en 404 verifie le 2026-09-04). Il ne reste dans la cascade que
  parce qu'il ne demande aucune cle, donc qu'il tient le plancher quand le prompt de la
  routine n'injecte pas `PEXELS_API_KEY`.
- **Les cles arrivent par le prompt de la routine**, jamais par le repo : les repos du
  reseau sont PUBLICS. Le script lit `PEXELS_API_KEY` et `UNSPLASH_ACCESS_KEY` dans
  l'environnement, et a defaut dans le `.env` du Drive quand il tourne sur un Mac. Sans
  cle, la cascade demarre a Openverse et l'article sort quand meme.
- **Le champ `image` du frontmatter n'est JAMAIS omis.** C'est la regle la plus importante
  de cette etape. Publier sans hero a laisse 9 articles FR sans aucun visuel entre le 10
  et le 26/08/2026.
- Reporter **la ligne 1 telle quelle** dans `image`. L'extension varie legitimement selon
  l'environnement : `.webp` quand `cwebp` est la, `.jpg` sur une machine sans lui, `.png`
  quand c'est le visuel genere. Une extension inventee produit un hero casse sans erreur
  de build.
- **Ligne 3 vide = visuel genere, donc pas de `imageCredit`** (on ne credite personne pour
  un visuel qu'on fabrique). Ligne 3 renseignee = photo d'une banque, et `imageCredit` est
  alors **obligatoire**, tel que renvoye. Pexels n'impose pas l'attribution et Unsplash l'exige,
  on la garde quand meme : c'est correct vis-a-vis du photographe et ca evite de traiter
  la ligne 3 differemment selon la source.
- Si le script sort quand meme non-zero (bug, ou `timeout` externe qui le tue avant le
  filet), ne pas marquer `failed` et ne pas publier sans image : generer le visuel a la
  main, puis renseigner `image`.
  ```bash
  python3 .claude/scripts/make-placeholder.py "<slug-fr>" "static/images/blog/<slug-fr>.png"
  ```
- **Regarder l'image avant de publier quand la ligne 3 est renseignee.** Le controle visuel
  reste obligatoire sur les trois banques : le score du script porte sur le ratio et la
  largeur, pas sur le sujet. Si l'image ne correspond pas au sujet, relancer le script avec
  une query plus concrete (un objet, un lieu, une action filmable) plutot qu'un concept
  abstrait, et en dernier ressort prendre le visuel genere.
- **Le script tient un registre `.claude/hero-sources.json`** (slug -> `banque:id`) et ECARTE
  tout candidat deja utilise par un autre article. Ne pas le vider : c'est ce qui empeche deux
  articles de porter la meme photo, defaut mesure le 2026-09-04 (2 paires de doublons sur un
  lot de 15, deux requetes voisines convergeant sur le meme cliche). Il est versionne, il ne
  contient que des identifiants publics de photos.
- **Noter la banque servie dans la ligne `MEMORY.md`** du run (`image hero: pexels`,
  `unsplash`, `openverse` ou `visuel genere`). C'est ce qui permettra de mesurer si la
  cascade tient dans le temps.

## Etape 6 — Maillage interne

1. Lister les `.md` de `content/fr/blog/` (hors `_index.md`).
2. Lire leur frontmatter : `title`, `categories`, `tags`, et le slug du fichier.
3. Scorer la proximite avec le nouvel article : categorie identique +3, tag partage +1 par tag, mot commun avec le `kw` +2.
4. Garder les 3 a 5 meilleurs.
5. Ancres en langue naturelle contenant le mot-cle de l'article cible.
6. Placer les liens de facon contextuelle dans le body, un par section. **Pas de bloc "Voir aussi" en fin d'article.**

**Maillage intra-langue strict** : la version FR pointe vers `/blog/...`, la version EN vers `/en/blog/...`. Ne jamais croiser.

**Verifier que chaque cible existe reellement** avant d'ecrire le lien : la cible doit etre un fichier present dans `content/fr/blog/` (respectivement `content/en/blog/`). Des liens internes morts ont deja ete introduits sur ce blog en recopiant les liens d'un article source.

## Etape 7 — Redaction FR

Fichier : `content/fr/blog/[slug-fr].md`.

### Frontmatter

```yaml
---
title: "[Title, <= 60 car, sans nom du site]"
translationKey: "[slug-generique-identique-FR-et-EN]"
date: "[YYYY-MM-DD]"
lastmod: "[YYYY-MM-DD]"
description: "[Meta description <= 155 car]"
categories: ["[Categorie FR exacte, cf. tableau etape 0]"]
tags: ["tag1", "tag2", "tag3", "tag4", "tag5"]
author: "[id-slug]"
auteurs: ["[id-slug]"]
image: "/images/blog/[slug].webp"
imageAlt: "[Description FR, <= 125 car]"
imageCredit: "[Credit exact renvoye par fetch-image.sh]"
faq:
  - question: "[Q1]"
    answer: "[R1, 3 a 5 phrases]"
  - question: "[Q2]"
    answer: "[R2, 2 a 4 phrases]"
---
```

**Le bloc `faq:` du frontmatter est obligatoire.** Il alimente le schema `FAQPage` de `layouts/partials/schema.html`. Les accordeons `<details>` du body ne suffisent pas : sans ce bloc, aucun balisage FAQ n'est genere. Les questions et reponses du frontmatter doivent etre **strictement identiques** a celles du body.

Les 2 axes de tags du blog : plateformes (`google`, `chatgpt`, `linkedin`, `tiktok`, `instagram`, `meta`...) et formats (`guide`, `comparatif`, `actu`, `interview`). Melanger les deux axes plus les tags de sujet.

### Body

- Premier paragraphe : contient le `kw` naturellement et pose le contexte, sans formule d'accroche creuse.
- Respecter la structure de l'etape 3, ni section en plus ni en moins.
- 1500 a 2000 mots.
- Densite du `kw` naturelle, 1 a 2 %. Variations et synonymes dans les H2.
- Mots-cles importants en **gras**, avec parcimonie.
- Au moins un tableau si l'etape 1.7 a note "tableau pertinent". Les tableaux passent par le render hook `layouts/_default/_markup/render-table.html` qui gere le scroll horizontal : ecrire du markdown de tableau standard, ne pas ecrire de HTML.
- Paragraphes de 3 a 5 phrases maximum.
- Liens internes de l'etape 6, places dans le corps des sections.
- Dernier H2 "Questions frequentes" en `<details><summary>`, aligne au mot pres sur le frontmatter `faq:`.

Relire le contenu produit contre la section "Regles editoriales non negociables" avant d'ecrire le fichier. Le controle typographique n'est pas optionnel :

```bash
grep -n "—\|–\|·" content/fr/blog/[slug-fr].md content/en/blog/[slug-en].md
```
Cette commande doit ne rien renvoyer. Si elle renvoie quelque chose, corriger avant de builder.

## Etape 7bis — Controle de score Datafer (non bloquant, une seule passe)

Uniquement si le mode retenu a l'etape 1.5 est `datafer`. Dans les autres modes, sauter cette etape.

Le brief cree a l'etape 1 sait scorer un contenu sur les memes criteres que les concurrents. On mesure l'article **avant** de le traduire et de le publier, pour corriger une fois si besoin.

### 7bis.1 Soumettre le contenu

`POST /api/v1/briefs/{id}/content` n'accepte que `<h1>`, `<h2>`, `<h3>` et `<p>`. Convertir le body FR : le `title` du frontmatter devient le `<h1>`, les `##` et `###` deviennent `<h2>` et `<h3>`, chaque paragraphe devient un `<p>`. Les tableaux, les listes et les accordeons `<details>` sont aplatis en `<p>`, les questions de FAQ en `<h3>` suivies de leur reponse en `<p>`. Les liens sont conserves en texte.

```bash
python3 - <<'PY' > /tmp/editor.json
# construire {"editorHtml": "..."} depuis content/fr/blog/<slug>.md
PY
curl -s --max-time 120 -X POST "$BASE/api/v1/briefs/$ID/content" \
  -H "Authorization: Bearer $DATAFER_API_KEY" \
  -H 'Content-Type: application/json' \
  --data @/tmp/editor.json
```

### 7bis.2 Lire le verdict

De la reponse, retenir `total`, `seoTotal`, `geoTotal`, le `breakdown` par critere (`keyword`, `nlpCoverage`, `contentLength`, `headings`, `placement`, `structure`, `quality`, `geo`) et `competitors.avg` / `competitors.best`.

**La barre est `competitors.avg`.** Un article du reseau qui sort en dessous de la moyenne du top 10 n'a pas de raison de passer devant.

### 7bis.3 Une passe d'enrichissement, jamais deux

Si `total >= competitors.avg` : ne rien changer, loguer le score, passer a l'etape 8.

Si `total < competitors.avg` : prendre les **deux criteres du `breakdown` les plus loin de leur `max`** et corriger uniquement ceux-la, dans le contenu existant, sans casser la structure validee a l'etape 3 :

- `nlpCoverage` faible : placer naturellement les `nlpTerms` a `presence >= 50` encore absents, en priorite ceux dont `inHeadings` est `true`. Jamais de bourrage, jamais une marque concurrente.
- `contentLength` faible : etoffer les sections les plus courtes jusqu'a atteindre `minWordCount` au minimum, en apportant du fond, pas du remplissage.
- `headings` faible : ajouter un H2 ou un H3 sur une `section` a fort `hits` non encore couverte.
- `structure` ou `placement` faible : replacer le `kw` dans le premier paragraphe et dans un H2, aerer les paragraphes trop longs.
- `quality` faible : casser les phrases trop longues, retirer les formulations creuses.

Puis **rescorer une seule fois** et loguer les deux scores. **On s'arrete la, quel que soit le second score.** Pas de troisieme passe : la routine a un creneau de publication a tenir, et un article legerement sous la moyenne publie vaut mieux qu'une boucle d'optimisation qui mange le run.

### 7bis.4 Ne jamais echouer sur cette etape

Un `409`, un `400 editorHtml required`, un timeout ou une reponse illisible se loguent en `SCORE : non mesure` et n'empechent ni la traduction ni la publication. Cette etape est un controle qualite, pas une condition de publication.

## Etape 8 — Redaction EN

Fichier : `content/en/blog/[slug-en].md`.

- **Meme `translationKey` que le FR**, a l'identique. C'est ce qui appaire les deux versions pour le hreflang et le switcher de langue. Une faute ici casse les deux silencieusement.
- Traduction fidele du FR, pas une nouvelle recherche de mots-cles.
- Slug EN traduit, pas translittere.
- `categories` en EN via le tableau de l'etape 0. `tags` traduits.
- `imageAlt` traduit. `image` et `imageCredit` identiques au FR.
- `author` et `auteurs` identiques au FR.
- Bloc `faq:` du frontmatter et accordeons du body traduits tous les deux.
- Memes interdits typographiques : ni cadratin, ni demi-cadratin, ni point median.

## Etape 9 — Build Hugo

### 9.0 Installer Hugo extended v0.161.1

Le sandbox cloud n'a pas Hugo, et la version fournie par `apt` (0.123.x) casse le build des sites multilingues du reseau. Installer exactement la version de la prod :

```bash
wget -q -O /tmp/hugo.deb https://github.com/gohugoio/hugo/releases/download/v0.161.1/hugo_extended_0.161.1_linux-amd64.deb \
  && (sudo dpkg -i /tmp/hugo.deb 2>/dev/null || { dpkg-deb -x /tmp/hugo.deb /tmp/hugobin && export PATH="/tmp/hugobin/usr/local/bin:$PATH"; })
hugo version   # doit afficher v0.161.1 extended
```

**Repli si le telechargement echoue en 403** (l'egress proxy du sandbox bloque `github.com/gohugoio/hugo/releases`, repo hors scope de la session, non debloquable car cross-owner) : passer par le wrapper npm, qui recupere le meme binaire et passe le proxy.

```bash
mkdir -p /tmp/hugobin-npm && cd /tmp/hugobin-npm && npm init -y >/dev/null 2>&1 && npm install hugo-extended@0.161.1
export PATH="/tmp/hugobin-npm/node_modules/.bin:$PATH"
hugo version
```

Si les deux echouent, utiliser le `hugo` present. **Ne jamais faire `apt install hugo`.** La version de la prod est dans `.github/workflows/hugo.yml`, s'y referer si elle a change.

### 9.1 Build et verification

```bash
hugo --gc --minify
```

- Exit code non-zero : marquer `failed` avec le log de l'erreur, abort.
- Verifier ensuite que les deux pages existent reellement dans le build :

```bash
ls public/blog/[slug-fr]/index.html public/en/blog/[slug-en]/index.html
```

Ce controle n'est pas cosmetique. Un article ecrit hors de `content/` a deja produit un 404 en production pendant plusieurs jours, **sans la moindre erreur de build**. Si un des deux fichiers manque, marquer `failed` avec l'erreur "page absente du build", meme si `hugo` a rendu 0.

## Etape 10 — Mise a jour roadmap et MEMORY.md

### roadmap.yaml

```yaml
  status: done
  published_date: "[YYYY-MM-DD]"
  published_url_fr: "https://journal-marketing.fr/blog/[slug-fr]/"
  published_url_en: "https://journal-marketing.fr/en/blog/[slug-en]/"
  error: null
```

### MEMORY.md

A la racine du repo. Le creer s'il n'existe pas, avec le titre `# MEMORY - Journal Marketing` suivi d'une section `## Publications`. Ajouter une ligne :

```
- YYYY-MM-DD | [Titre FR] (FR+EN) | [Categorie] | auto | AIO: [Declenchee|Non declenchee] | mode: [datafer|crazyserp|websearch|degrade] | score: [total]/[competitors.avg]
```

Le suffixe `auto` distingue ces articles de ceux produits a la main.

## Etape 11 — Commit et push

```bash
git add -A
git commit -m "Auto: publication evergreen - [Titre FR] (mode: [datafer|crazyserp|websearch|degrade], score: [total]/[avg])"
git pull --rebase origin main
git push origin main
```

Push rejete apres rebase : retenter jusqu'a 3 fois (`pull --rebase` puis `push`). Toujours KO au bout de 3 : marquer `failed` avec l'erreur "push rejected 3x", commit du roadmap local, exit non-zero.

Le push sur `main` declenche le workflow GitHub Actions qui deploie sur GitHub Pages.

## Gestion des echecs (transversal)

A n'importe quelle etape, hors les deux exceptions listees plus haut :

1. Loguer le message d'erreur precis (etape et cause).
2. Mettre a jour l'entree de roadmap :
   ```yaml
     status: failed
     error: "[etape] [message]"
   ```
3. Supprimer les fichiers d'article partiellement ecrits, pour ne pas laisser de brouillon dans `content/`.
4. Commit du seul `roadmap.yaml`, message `Auto: roadmap update (failed)`.
5. Push.
6. Exit non-zero.

Une entree `failed` n'est **jamais** retentee automatiquement. Damien la corrige et la repasse en `todo`.

## Format de roadmap.yaml

```yaml
articles:
  - kw: "mot cle principal"
    category: "Une des 7 rubriques"
    volume: 1200        # informatif, ignore par l'agent
    kd: 35              # informatif, ignore par l'agent
    scheduled_date: "2026-08-10"
    status: todo
    published_date: null
    published_url_fr: null
    published_url_en: null
    error: null
```

Champs editables par l'humain : `kw`, `category`, `scheduled_date` (obligatoires), `volume` et `kd` (informatifs, **ignores par l'agent**), `status` (pour repasser un `failed` en `todo`).

Champs remplis par l'agent : `published_date`, `published_url_fr`, `published_url_en`, `error`, et bascule de `status`.

**Cadence : 5 articles par semaine, du lundi au vendredi** (cron `0 1 * * 1-5`), un seul par run.

Les 7 rubriques tournent dans un **cycle continu qui enjambe les semaines** : SEO, Contenu, Publicite en ligne, IA et GEO, Data et mesure, Social et influence, Outils et comparatifs, puis on reboucle. Avec 5 jours ouvres pour 7 rubriques, une semaine ne couvre jamais tout le site : la semaine suivante reprend la rotation la ou elle s'etait arretee. Chaque rubrique revient donc tous les 7 articles.

En rechargeant la roadmap, **poursuivre le cycle la ou la derniere entree l'a laisse**, ne pas le remettre a zero sur le lundi. Ne programmer que des jours ouvres.

## Logs

Ecrire le deroulement dans `/tmp/create-article-auto-[YYYY-MM-DD-HHMM].log` :
- mot-cle et categorie traites,
- mode SERP reellement utilise (`crazyserp`, `websearch`, `degrade`) et `credits_used` si CrazySERP,
- `params.location` renvoye par CrazySERP,
- AIO declenchee ou non,
- auteur selectionne et raison,
- image recuperee (chemin et credit) ou absence,
- nombre de liens internes places,
- resultat du controle typographique,
- resultat du controle de presence des deux pages dans `public/`,
- temps total et exit code.
