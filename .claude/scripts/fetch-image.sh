#!/bin/bash
# fetch-image.sh
# Recupere une image libre de droit compatible usage commercial pour le hero d'un article.
#
# CASCADE DE SOURCES (2026-09-04). L'ordre n'est pas negociable, il est le resultat
# d'une mesure sur les 45 articles FR du blog :
#   0. Banque centrale datashake, si et seulement si `tools/banque-images/bank-pick.py`
#      est trouve en remontant les dossiers parents. Elle sert les photos OFFICIELLES du
#      client en priorite, ce qui doit toujours primer sur une photo de stock. Palier
#      introduit sur lulli-magazine et tribune-inextenso par un autre consultant : il est
#      conserve ici pour ne pas ecraser cette intention. **Au 2026-09-04 la banque n'existe
#      nulle part dans ~/code**, donc ce palier est inactif et le script passe au suivant.
#   1. Pexels    — banque commerciale, indexation marketing, ratio paysage garanti.
#   2. Unsplash  — repli. Plafonne a 50 req/h en mode Demo, et ses guidelines imposent
#      de pinger `links.download_location` a chaque telechargement : c'est fait plus bas,
#      ne pas le retirer, c'est une condition d'utilisation de l'API.
#   3. Openverse — DERNIER RECOURS uniquement. Il federe Flickr et Wikimedia, donc des
#      archives et des photos perso : le filtre de licence ne dit rien de la pertinence.
#      Mesure du 2026-09-04 sur les 45 heros du blog : 10 photos franchement hors sujet
#      (salle de controle de bus pour Looker Studio, conseil d'administration pour la
#      ligne editoriale, ecran gov.uk pour le web analytics) et 15 photos generiques
#      interchangeables. Il ne reste dans la cascade que parce qu'il ne demande AUCUNE
#      cle : c'est le plancher tant que le prompt de la routine n'injecte pas les cles.
#   4. Placeholder de charte genere en local — ne peut jamais echouer.
#
# ANTI-DOUBLON. Deux requetes voisines convergent sur la meme photo : le scoring prend
# toujours le meilleur candidat, donc « seo analysis laptop report » et « website traffic
# analytics graph laptop » rendaient le MEME cliche (mesure du 2026-09-04, 2 paires de
# doublons sur un lot de 15). Le script tient donc un registre `.claude/hero-sources.json`
# (slug -> "<banque>:<id>") et ECARTE tout candidat deja utilise par un autre article.
# Le registre est versionne dans le repo : il ne contient que des identifiants publics de
# photos, aucune donnee sensible.
#
# CLES. Les repos du reseau sont PUBLICS : aucune cle n'est ecrite ici. Le script les lit
# dans l'environnement (`PEXELS_API_KEY`, `UNSPLASH_ACCESS_KEY`), injecte par le prompt de
# la routine, et a defaut dans le `.env` local du Drive quand il tourne sur un Mac.
# Sans cle, la cascade demarre directement a Openverse : le run publie quand meme.
#
# Usage : fetch-image.sh "<query>" "<slug>" [output_dir]
# Output stdout (3 lignes, contrat inchange) :
#   ligne 1 : chemin Hugo de l'image (ex: /images/blog/mon-slug.webp)
#   ligne 2 : alt text suggere
#   ligne 3 : credit, ou VIDE si le visuel a ete genere (= pas de imageCredit)
# Output stderr : messages d'info/erreur
# Exit codes : 0 OK (y compris placeholder), 1 args, 6 placeholder impossible

set -uo pipefail

QUERY="${1:-}"
SLUG="${2:-}"
OUTPUT_DIR="${3:-static/images/blog}"

if [ -z "$QUERY" ] || [ -z "$SLUG" ]; then
    echo "Usage: $0 <query> <slug> [output_dir]" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

USER_AGENT="blog-site-template/2.0 (+https://github.com/analytics-ds)"
SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

QUERY_ENCODED=$(printf '%s' "$QUERY" | python3 -c "import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip()))" 2>/dev/null || echo "$QUERY" | sed 's/ /+/g')

# --- Resolution des cles ------------------------------------------------------
# Priorite a l'environnement (cas de la routine cloud). A defaut, on cherche un
# `.env` sur le Mac sans jamais ecrire de chemin nominatif dans ce repo public.
key_from_env_file() {
    local name="$1" f
    for f in "$HOME"/*Drive*/*/.claude/secrets/.env "$HOME"/.claude/secrets/.env; do
        [ -f "$f" ] || continue
        local v
        v=$(grep -m1 "^${name}=" "$f" 2>/dev/null | cut -d= -f2- | tr -d '"' | tr -d '\r')
        if [ -n "${v:-}" ]; then printf '%s' "$v"; return 0; fi
    done
    return 1
}

PEXELS_KEY="${PEXELS_API_KEY:-}"
[ -z "$PEXELS_KEY" ] && PEXELS_KEY="$(key_from_env_file PEXELS_API_KEY || true)"
UNSPLASH_KEY="${UNSPLASH_ACCESS_KEY:-}"
[ -z "$UNSPLASH_KEY" ] && UNSPLASH_KEY="$(key_from_env_file UNSPLASH_ACCESS_KEY || true)"

IMAGE_URL=""
IMAGE_TITLE=""
IMAGE_CREDIT=""
IMAGE_SOURCE=""
IMAGE_ID=""

# --- Filet de securite : placeholder genere en local -------------------------
# Sans ce filet, la skill publiait l'article SANS AUCUN visuel : 9 articles FR sur 14
# entre le 10 et le 26/08/2026. Un placeholder de charte vaut mieux qu'un hero vide,
# et il ne peut jamais echouer puisqu'il ne sort pas de la machine.
emit_placeholder() {
    local reason="$1"
    local out="$OUTPUT_DIR/$SLUG.png"
    local gen="$SCRIPT_DIR/make-placeholder.py"
    if [ ! -f "$gen" ]; then
        echo "[fetch-image] ERREUR : make-placeholder.py introuvable a cote du script" >&2
        exit 6
    fi
    if ! python3 "$gen" "$SLUG" "$out" >/dev/null; then
        echo "[fetch-image] ERREUR : generation du placeholder echouee" >&2
        exit 6
    fi
    echo "[fetch-image] PLACEHOLDER genere ($reason) : $out" >&2
    local hp
    hp=$(echo "$out" | sed -E 's|^\.?/?static/|/|')
    [[ "$hp" != /* ]] && hp="/$hp"
    echo "$hp"
    echo ""
    echo ""
    exit 0
}

# --- Appel HTTP avec retry ---------------------------------------------------
# `|| true` obligatoire : un curl non-zero (proxy egress, DNS, timeout) ne doit
# jamais tuer la cascade avant le palier suivant.
http_get_json() {
    local url="$1" tmp="/tmp/imgapi-$$.json" http
    shift
    local i
    for i in 1 2 3; do
        http=$(curl -sL --max-time 25 -w '%{http_code}' -o "$tmp" \
            -H "User-Agent: $USER_AGENT" -H "Accept: application/json" \
            "$@" "$url" || echo "000")
        if [ "$http" = "200" ]; then
            cat "$tmp"; rm -f "$tmp"; return 0
        fi
        # 401/403 = cle absente ou invalide : inutile de retenter, on passe au palier suivant
        if [ "$http" = "401" ] || [ "$http" = "403" ]; then
            echo "[fetch-image] HTTP $http (cle refusee), palier suivant" >&2
            rm -f "$tmp"; return 1
        fi
        echo "[fetch-image] HTTP $http (tentative $i/3)" >&2
        sleep $((i * 2))
    done
    rm -f "$tmp"
    return 1
}

# Scoring commun. Le hero est rendu en 1200x520 (ratio 2.31) en object-fit: cover.
# Prendre le 1er resultat donnait des portraits recadres aux 3/4 et des vignettes
# de 500px upscalees, d'ou ce score sur le ratio et la largeur.
read -r -d '' SCORER <<'PY' || true
import os as _os, json as _json
try:
    USED = set(_json.loads(_os.environ.get('USED_IDS_JSON') or '[]'))
except Exception:
    USED = set()
def already_used(bank, pid):
    return f'{bank}:{pid}' in USED
TARGET_RATIO = 2.31
def score(w, h):
    if not w or not h:
        return -1e9
    ratio = w / h
    pen = abs(ratio - TARGET_RATIO) * (60.0 if ratio < 1.0 else 22.0)
    bonus = min(w, 1600) / 20.0
    if w < 900:
        bonus -= 45.0
    return bonus - pen
PY

# --- Registre anti-doublon ---------------------------------------------------
LEDGER=".claude/hero-sources.json"
USED_IDS_JSON=$(python3 - "$LEDGER" "$SLUG" <<'PYL' 2>/dev/null || echo '[]'
import json, sys, os
path, slug = sys.argv[1], sys.argv[2]
used = []
if os.path.exists(path):
    try:
        d = json.load(open(path, encoding='utf-8'))
        # on n'exclut pas l'entree du slug courant : on a le droit de reprendre sa propre photo
        used = [v for k, v in d.items() if k != slug and v]
    except Exception:
        used = []
print(json.dumps(used))
PYL
)
export USED_IDS_JSON
echo "[fetch-image] registre : $(printf '%s' "$USED_IDS_JSON" | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0) photos deja utilisees" >&2

# Enregistre le couple slug -> banque:id apres un telechargement reussi.
record_in_ledger() {
    [ -n "${IMAGE_ID:-}" ] || return 0
    python3 - "$LEDGER" "$SLUG" "${IMAGE_SOURCE}:${IMAGE_ID}" <<'PYW2' || true
import json, sys, os
path, slug, val = sys.argv[1], sys.argv[2], sys.argv[3]
d = {}
if os.path.exists(path):
    try:
        d = json.load(open(path, encoding='utf-8'))
    except Exception:
        d = {}
d[slug] = val
os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
json.dump(dict(sorted(d.items())), open(path, 'w', encoding='utf-8'), indent=2, ensure_ascii=False)
open(path, 'a', encoding='utf-8').write('\n')
PYW2
    echo "[fetch-image] registre mis a jour : $SLUG -> ${IMAGE_SOURCE}:${IMAGE_ID}" >&2
}

# --- Palier 0 : banque centrale datashake (photos officielles client) --------
# Ce palier vient de lulli-magazine et tribune-inextenso, ou un autre consultant l'avait
# ajoute pour que les photos OFFICIELLES du client passent avant toute photo de stock.
# Il est conserve tel quel, avec ses deux subtilites qu'il ne faut pas perdre :
#   - le picker renvoie un CHEMIN DE FICHIER LOCAL, pas une URL : on copie, on ne telecharge
#     pas (un curl sur un chemin local echoue en silence et fait perdre le visuel client) ;
#   - il ecrit sur stderr des alertes utiles (visuel sur-utilise, theme sature) qu'on relaie.
# Au 2026-09-04 le picker n'existe nulle part dans ~/code, donc ce palier est inactif.
try_bank() {
    local picker="" _d="$PWD" _i
    for _i in 1 2 3 4 5 6 7 8; do
        if [ -f "$_d/tools/banque-images/bank-pick.py" ]; then picker="$_d/tools/banque-images/bank-pick.py"; break; fi
        [ "$_d" = "/" ] && break
        _d="$(dirname "$_d")"
    done
    [ -n "$picker" ] || return 1
    echo "[fetch-image] banque centrale trouvee : $picker" >&2
    local err out
    err=$(mktemp)
    if ! out=$(python3 "$picker" "$QUERY" "$SLUG" 2>"$err"); then
        [ -s "$err" ] && cat "$err" >&2
        rm -f "$err"
        echo "[fetch-image] banque : pas de match, palier suivant" >&2
        return 1
    fi
    [ -s "$err" ] && cat "$err" >&2
    rm -f "$err"
    local src alt credit
    src=$(sed -n '1p' <<< "$out")
    alt=$(sed -n '2p' <<< "$out")
    credit=$(sed -n '3p' <<< "$out")
    [ -z "$credit" ] && credit="Photo via Pexels (usage commercial, sans attribution requise)"
    if [ -z "$src" ] || [ ! -f "$src" ]; then
        echo "[fetch-image] banque : chemin invalide ($src), palier suivant" >&2
        return 1
    fi
    OUTPUT_FILE="$OUTPUT_DIR/$SLUG.webp"
    cp "$src" "$OUTPUT_FILE"
    IMAGE_SOURCE="banque"
    IMAGE_ID="$(basename "$src")"
    record_in_ledger
    local hp
    hp=$(printf '%s' "$OUTPUT_FILE" | sed -E 's|^\.?/?static/|/|')
    case "$hp" in /*) ;; *) hp="/$hp" ;; esac
    echo "[fetch-image] banque centrale : match, $OUTPUT_FILE" >&2
    printf '%s\n%s\n%s\n' "$hp" "$alt" "$credit"
    exit 0
}

# --- Palier 1 : Pexels -------------------------------------------------------
try_pexels() {
    [ -n "$PEXELS_KEY" ] || { echo "[fetch-image] Pexels : pas de cle, palier suivant" >&2; return 1; }
    echo "[fetch-image] Pexels : $QUERY" >&2
    local json
    json=$(http_get_json \
        "https://api.pexels.com/v1/search?query=${QUERY_ENCODED}&per_page=15&orientation=landscape&size=large" \
        -H "Authorization: $PEXELS_KEY") || return 1
    local res
    res=$(printf '%s' "$json" | python3 -c "
import sys, json
$SCORER
data = json.load(sys.stdin)
photos = data.get('photos') or []
cands = []
skipped = 0
for p in photos:
    src = p.get('src') or {}
    u = src.get('large2x') or src.get('original') or src.get('large') or src.get('landscape')
    if not u:
        continue
    if already_used('pexels', p.get('id')):
        skipped += 1
        continue
    cands.append((score(p.get('width') or 0, p.get('height') or 0), p, u))
if skipped:
    print(f'[fetch-image] Pexels : {skipped} candidat(s) ecarte(s), deja utilises ailleurs', file=sys.stderr)
if not cands:
    sys.exit(3)
cands.sort(key=lambda c: c[0], reverse=True)
_s, p, u = cands[0]
print(f\"[fetch-image] Pexels retenu {p.get('width')}x{p.get('height')} sur {len(cands)} candidats\", file=sys.stderr)
print(u)
print((p.get('alt') or '').strip())
print(f\"Photo par {p.get('photographer') or 'Auteur inconnu'} via Pexels\")
print(p.get('id') or '')
") || { echo "[fetch-image] Pexels : aucun resultat exploitable" >&2; return 1; }
    IMAGE_URL=$(sed -n '1p' <<< "$res")
    IMAGE_TITLE=$(sed -n '2p' <<< "$res")
    IMAGE_CREDIT=$(sed -n '3p' <<< "$res")
    IMAGE_ID=$(sed -n '4p' <<< "$res")
    IMAGE_SOURCE="pexels"
    [ -n "$IMAGE_URL" ]
}

# --- Palier 2 : Unsplash -----------------------------------------------------
UNSPLASH_DL=""
try_unsplash() {
    [ -n "$UNSPLASH_KEY" ] || { echo "[fetch-image] Unsplash : pas de cle, palier suivant" >&2; return 1; }
    echo "[fetch-image] Unsplash : $QUERY" >&2
    local json
    json=$(http_get_json \
        "https://api.unsplash.com/search/photos?query=${QUERY_ENCODED}&per_page=15&orientation=landscape" \
        -H "Authorization: Client-ID $UNSPLASH_KEY") || return 1
    local res
    res=$(printf '%s' "$json" | python3 -c "
import sys, json
$SCORER
data = json.load(sys.stdin)
results = data.get('results') or []
cands = []
skipped = 0
for r in results:
    urls = r.get('urls') or {}
    u = urls.get('raw') or urls.get('full') or urls.get('regular')
    if not u:
        continue
    if already_used('unsplash', r.get('id')):
        skipped += 1
        continue
    cands.append((score(r.get('width') or 0, r.get('height') or 0), r, u))
if skipped:
    print(f'[fetch-image] Unsplash : {skipped} candidat(s) ecarte(s), deja utilises ailleurs', file=sys.stderr)
if not cands:
    sys.exit(3)
cands.sort(key=lambda c: c[0], reverse=True)
_s, r, u = cands[0]
# 'raw' est la source non bornee : on lui impose la largeur cible cote CDN Unsplash
if 'images.unsplash.com' in u:
    u += ('&' if '?' in u else '?') + 'w=1600&q=82&fm=jpg&fit=max'
print(f\"[fetch-image] Unsplash retenu {r.get('width')}x{r.get('height')} sur {len(cands)} candidats\", file=sys.stderr)
print(u)
print((r.get('alt_description') or r.get('description') or '').strip())
print(f\"Photo par {(r.get('user') or {}).get('name') or 'Auteur inconnu'} via Unsplash\")
print((r.get('links') or {}).get('download_location') or '')
print(r.get('id') or '')
") || { echo "[fetch-image] Unsplash : aucun resultat exploitable" >&2; return 1; }
    IMAGE_URL=$(sed -n '1p' <<< "$res")
    IMAGE_TITLE=$(sed -n '2p' <<< "$res")
    IMAGE_CREDIT=$(sed -n '3p' <<< "$res")
    UNSPLASH_DL=$(sed -n '4p' <<< "$res")
    IMAGE_ID=$(sed -n '5p' <<< "$res")
    IMAGE_SOURCE="unsplash"
    [ -n "$IMAGE_URL" ]
}

# Ping de comptage impose par les guidelines Unsplash. Non bloquant : un echec ici
# ne doit jamais couter l'image, mais il ne faut pas le supprimer pour autant.
ping_unsplash_download() {
    [ -n "$UNSPLASH_DL" ] || return 0
    curl -s -o /dev/null --max-time 10 -H "Authorization: Client-ID $UNSPLASH_KEY" "$UNSPLASH_DL" || true
    echo "[fetch-image] Unsplash : download_location pingue" >&2
}

# --- Palier 3 : Openverse (dernier recours, sans cle) ------------------------
# RETRY : Openverse renvoie des 500 de facon intermittente sur des requetes
# parfaitement valides (mesure du 2026-08-27 : "smartphone" et "laptop" en 500
# quand "influencer" rendait 240 resultats dans la meme minute).
try_openverse() {
    echo "[fetch-image] Openverse (dernier recours) : $QUERY" >&2
    local json
    json=$(http_get_json \
        "https://api.openverse.org/v1/images/?q=${QUERY_ENCODED}&license_type=commercial,modification&page_size=20&mature=false") || return 1
    printf '%s' "$json" | grep -q '^{"detail":' && { echo "[fetch-image] Openverse : reponse d'erreur" >&2; return 1; }
    local res
    res=$(printf '%s' "$json" | python3 -c "
import sys, json
$SCORER
data = json.load(sys.stdin)
results = data.get('results') or []
cands = [r for r in results if r.get('url') and not already_used('openverse', r.get('id'))]
if not cands:
    sys.exit(3)
cands.sort(key=lambda r: score(r.get('width') or 0, r.get('height') or 0), reverse=True)
r = cands[0]
print(f\"[fetch-image] Openverse retenu {r.get('width')}x{r.get('height')} sur {len(cands)} candidats\", file=sys.stderr)
print(r.get('url') or '')
print(r.get('title') or '')
lic = (r.get('license') or '').upper()
ver = r.get('license_version') or ''
lic = f'CC {lic} {ver}'.strip() if lic else 'CC'
src = (r.get('source') or r.get('provider') or '')
print(f\"Photo par {r.get('creator') or 'Auteur inconnu'} via {src.capitalize()} ({lic})\")
print(r.get('id') or '')
") || { echo "[fetch-image] Openverse : aucun resultat pour '$QUERY'" >&2; return 1; }
    IMAGE_URL=$(sed -n '1p' <<< "$res")
    IMAGE_TITLE=$(sed -n '2p' <<< "$res")
    IMAGE_CREDIT=$(sed -n '3p' <<< "$res")
    IMAGE_ID=$(sed -n '4p' <<< "$res")
    IMAGE_SOURCE="openverse"
    [ -n "$IMAGE_URL" ]
}

# --- Cascade -----------------------------------------------------------------
try_bank || try_pexels || try_unsplash || try_openverse || emit_placeholder "aucune-source"

# --- Telechargement ----------------------------------------------------------
TMP_FILE="/tmp/hero-${SLUG}.img"
echo "[fetch-image] Telechargement ($IMAGE_SOURCE) : $IMAGE_URL" >&2
curl -sL --max-time 30 -H "User-Agent: $USER_AGENT" "$IMAGE_URL" -o "$TMP_FILE" || true

if [ ! -s "$TMP_FILE" ]; then
    echo "[fetch-image] telechargement echoue (proxy egress du sandbox ?)" >&2
    rm -f "$TMP_FILE"
    emit_placeholder "download-bloque-$IMAGE_SOURCE"
fi

[ "$IMAGE_SOURCE" = "unsplash" ] && ping_unsplash_download

FILE_TYPE=$(file -b --mime-type "$TMP_FILE")
case "$FILE_TYPE" in
    image/jpeg) SRC_EXT="jpg" ;;
    image/png)  SRC_EXT="png" ;;
    image/webp) SRC_EXT="webp" ;;
    image/gif)  SRC_EXT="gif" ;;
    *)
        echo "[fetch-image] format non supporte ($FILE_TYPE)" >&2
        rm -f "$TMP_FILE"
        emit_placeholder "format-$FILE_TYPE"
    ;;
esac

# Conversion WebP + REDIMENSIONNEMENT.
# Le hero est rendu en 1200 px de large : une source de 3000 a 6000 px partait
# telle quelle et pesait jusqu'a 826 Ko en `fetchpriority=high`, donc directement
# dans le LCP. On plafonne a 1600 px (marge pour les ecrans 2x) et q82.
MAX_W=1600
if command -v cwebp >/dev/null 2>&1; then
    OUTPUT_FILE="$OUTPUT_DIR/$SLUG.webp"
    SRC_W=$(python3 - "$TMP_FILE" <<'PYW' 2>/dev/null || echo 0
import sys, struct
b=open(sys.argv[1],'rb').read()
w=0
try:
    if b[:2]==b'\xff\xd8':
        i=2
        while i<len(b)-9:
            if b[i]!=0xFF: i+=1; continue
            m=b[i+1]
            if m in (0xC0,0xC1,0xC2,0xC3):
                w=struct.unpack(">H", b[i+7:i+9])[0]; break
            if m in (0xD8,0xD9) or 0xD0<=m<=0xD7: i+=2; continue
            i+=2+struct.unpack(">H", b[i+2:i+4])[0]
    elif b[:8]==b'\x89PNG\r\n\x1a\n':
        w=struct.unpack(">I", b[16:20])[0]
    elif b[:4]==b'RIFF' and b[8:12]==b'WEBP':
        if b[12:16]==b'VP8X': w=int.from_bytes(b[24:27],'little')+1
        elif b[12:16]==b'VP8 ':
            i=b.find(b'\x9d\x01\x2a')
            if i>0: w=int.from_bytes(b[i+3:i+5],'little')&0x3fff
        elif b[12:16]==b'VP8L':
            w=(int.from_bytes(b[21:25],'little')&0x3fff)+1
except Exception:
    w=0
print(w)
PYW
)
    if [ "${SRC_W:-0}" -gt "$MAX_W" ] 2>/dev/null; then
        cwebp -quiet -q 82 -resize "$MAX_W" 0 "$TMP_FILE" -o "$OUTPUT_FILE"
        echo "[fetch-image] Converti en WebP + redimensionne a ${MAX_W}px : $OUTPUT_FILE" >&2
    else
        cwebp -quiet -q 82 "$TMP_FILE" -o "$OUTPUT_FILE"
        echo "[fetch-image] Converti en WebP : $OUTPUT_FILE" >&2
    fi
elif command -v sips >/dev/null 2>&1; then
    OUTPUT_FILE="$OUTPUT_DIR/$SLUG.$SRC_EXT"
    cp "$TMP_FILE" "$OUTPUT_FILE"
    sips -Z "$MAX_W" "$OUTPUT_FILE" >/dev/null 2>&1 || true
    echo "[fetch-image] cwebp absent, $SRC_EXT redimensionne par sips : $OUTPUT_FILE" >&2
elif [ "$SRC_EXT" = "webp" ]; then
    OUTPUT_FILE="$OUTPUT_DIR/$SLUG.webp"
    cp "$TMP_FILE" "$OUTPUT_FILE"
    echo "[fetch-image] Image deja en WebP, non redimensionnee : $OUTPUT_FILE" >&2
else
    # cas de l'environnement cloud : aucun outil d'image, on conserve la source
    OUTPUT_FILE="$OUTPUT_DIR/$SLUG.$SRC_EXT"
    cp "$TMP_FILE" "$OUTPUT_FILE"
    echo "[fetch-image] aucun outil d'image, conserve en $SRC_EXT : $OUTPUT_FILE" >&2
fi

rm -f "$TMP_FILE"

record_in_ledger

HUGO_PATH=$(echo "$OUTPUT_FILE" | sed -E 's|^\.?/?static/|/|')
[[ "$HUGO_PATH" != /* ]] && HUGO_PATH="/$HUGO_PATH"

echo "$HUGO_PATH"
echo "$IMAGE_TITLE"
echo "$IMAGE_CREDIT"
