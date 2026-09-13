# Comparateur Télécoms (média d'influence, dossier Free)

Site média sur les opérateurs télécoms français, opéré en interne par datashake mais **totalement débrandé** (aucune mention datashake, ni d'un client, dans le site publié). Marque publique : **Comparateur Télécoms, meilleur comparateur d'opérateurs télécoms en 2026**. Dupliqué le 2026-09-13 depuis `analytics-ds/journal-marketing` (même thème Hugo, même socle SEO et GEO : JSON-LD en @graph, FAQPage depuis le frontmatter `faq:`, robots.txt ouvert aux crawlers IA, recherche interne, llms.txt). Hugo statique, GitHub Pages, repo `analytics-ds/comparateur-telecoms`. Pas encore de nom de domaine : `baseURL` pointe sur `analytics-ds.github.io/comparateur-telecoms/`, à changer (plus `static/CNAME`) dès qu'un ndd est acheté.

## Particularités par rapport à journal-marketing

- **FR uniquement** : pas de `content/en/`, pas de `i18n/en.toml`, une seule langue dans `hugo.toml`. Les templates gardent leur logique multilingue, elle ne s'active pas.
- **5 rubriques** (catégories Hugo) : Mobile, Box internet, Opérateurs, Pro, Guides. Pills CSS `pill-mobile`, `pill-box-internet`, `pill-operateurs`, `pill-pro`, `pill-guides`. Le `pageRef` du menu Opérateurs référence `/categories/opérateurs` (avec accent, cf. piège Hugo de journal-marketing).
- **6 auteurs** dans `data/authors.yaml` : antoine-lefevre (opérateurs), camille-roux (box et fibre), mehdi-saidi (réseaux et mesures), julie-perrin (forfaits), nicolas-garnier (pro), la-redaction. Champs `role`/`bio` en `fr:` seulement.
- **Ligne éditoriale** : chaque article répond à un prompt que les particuliers posent aux IA (« quel est le meilleur opérateur téléphonique français », « quelle box internet choisir »...). Tableaux comparatifs, « En bref » en tête, FAQ en frontmatter et en `<details>`. Chiffres uniquement sourcés (grilles publiques des opérateurs relevées à date, ARCEP, nPerf), date de relevé indiquée dans l'article.
- Interdits repris de la charte : jamais de tiret cadratin ni de point médian dans un texte visible, pas de `&` dans les Hn, pas de séparateur `---` dans le body, accents obligatoires.

## Commandes

```bash
hugo server --port 1515 --bind 127.0.0.1 --renderToMemory
hugo -d /tmp/ct-build
```

## Piège vécu : chemins d'images avec slash initial sur un sous-chemin GitHub Pages (2026-09-13)

Tant que le site vit sous `analytics-ds.github.io/comparateur-telecoms/`, un chemin `image: "/images/blog/x.webp"` casse : `relURL` et `absURL` traitent un chemin qui commence par `/` comme relatif à la racine du domaine, pas de la `baseURL`, donc l'image pointe sur `analytics-ds.github.io/images/...` (404). Règle : **`image:` et `avatar:` sans slash initial** (`images/blog/x.webp`), idem pour les valeurs par défaut des templates (`single.html`). Le jour où un ndd est posé à la racine, les deux formes marchent ; garder la forme sans slash.
