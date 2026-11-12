#!/usr/bin/env bash
# Contrôle les fichiers d'une version de Mouflon, avant qu'elle reste publiée
# ici :
#
#   bash scripts/check-release.sh <dossier des fichiers> <numéro, comme 1.0.5> [<fichier de la clé>]
#
# Une version, ce sont sept fichiers, aux noms fixes (la page de présentation
# et les Mouflon installés pointent sur …/releases/latest/download/<nom>) :
#
#   Mouflon-macos-arm64.zip        l'app pour Mac, signée et notarisée
#   Mouflon-windows-x64.zip        le dossier pour Windows
#   Mouflon-linux-x86_64.tar.gz    l'aperçu pour Linux
#   Mouflon-source.zip             le code source de cette version
#   SHA256SUMS                     les sommes de contrôle de ces quatre-là
#   Mouflon-version.txt            leur liste (numéro de la version ; nom,
#                                  taille et somme SHA-512 de chacun)
#   Mouflon-version.txt.sig        la signature de cette liste par l'auteur
#
# Mouflon est open source par ses versions : sans l'archive du code de cette
# version-là, avec ses deux licences, rien ne reste publié.
#
# Mouflon se met à jour tout seul : un Mouflon installé lit la liste, vérifie
# qu'elle est signée par la clé de l'auteur (cle-de-signature.pub, à la
# racine de ce dépôt ; chaque Mouflon la porte), et n'installe que ce qu'elle
# annonce. Une liste fausse ou mal signée ne reste donc pas publiée non plus.
set -euo pipefail

DIR="${1:?le dossier des fichiers de la version}"
VERSION="${2:?le numéro de la version, comme 1.0.5}"
CLE_DE_L_AUTEUR="${3:-$(cd "$(dirname "$0")/.." && pwd)/cle-de-signature.pub}"
LISTE="Mouflon-version.txt"
PROGRAMMES="Mouflon-linux-x86_64.tar.gz Mouflon-macos-arm64.zip Mouflon-source.zip Mouflon-windows-x64.zip"
# Les seuls fichiers Markdown que l'archive du code peut contenir : ses
# crédits, son README, les trois modes d'emploi pour créer un animal, et les
# sources (ce qui a été lu et regardé pour les races, l'animation, les sons).
MARKDOWN="CREDITS.md README.md docs/format.md docs/rig.md docs/sources.md docs/squelette.md"
# Ses seuls fichiers et dossiers cachés, tous à sa racine.
CACHES=".gitattributes .github .gitignore"

rate() { echo "::error::$*"; exit 1; }
# contient <liste> <chemin> : la liste d'une archive nomme ce chemin.
contient() { grep -qxF -- "$2" <<< "$1"; }
# dit <archive zip> <chemin> <texte> : ce fichier de l'archive contient ce
# texte. (`grep` lit tout : avec `-q`, il fermerait le tuyau avant la fin.)
dit() { unzip -p "$1" "$2" | grep -F -- "$3" > /dev/null; }

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || rate "$VERSION n'est pas un numéro de version"

# ── Les sept fichiers, et rien d'autre ──────────────────────────────────────
ATTENDUS="Mouflon-linux-x86_64.tar.gz Mouflon-macos-arm64.zip Mouflon-source.zip $LISTE $LISTE.sig Mouflon-windows-x64.zip SHA256SUMS"
TROUVES="$(ls -A "$DIR" | LC_ALL=C sort | tr '\n' ' ')"
[[ "$TROUVES" == "$ATTENDUS " ]] \
    || rate "la version devrait avoir « $ATTENDUS », et elle a « ${TROUVES% } »"

# ── Les sommes de contrôle ──────────────────────────────────────────────────
NOMMES="$(awk '{ sub(/^\*/, "", $2); print $2 }' "$DIR/SHA256SUMS" | LC_ALL=C sort | tr '\n' ' ')"
[[ "$NOMMES" == "$PROGRAMMES " ]] || rate "SHA256SUMS devrait nommer « $PROGRAMMES », et il nomme « ${NOMMES% } »"
( cd "$DIR" && sha256sum --check --strict --quiet SHA256SUMS ) \
    || rate "un fichier n'a pas la somme de contrôle annoncée dans SHA256SUMS"

# ── Le code source : celui de cette version, avec ses deux licences ─────────
CODE="$(unzip -Z1 "$DIR/Mouflon-source.zip")" || rate "Mouflon-source.zip ne se lit pas"
P="Mouflon-$VERSION"
! grep -qv "^${P//./\\.}/" <<< "$CODE" || rate "Mouflon-source.zip devrait tenir tout entier dans le dossier $P/"
for f in LICENSE-MIT LICENSE-APACHE CREDITS.md README.md Cargo.toml Cargo.lock; do
    contient "$CODE" "$P/$f" || rate "le code source n'a pas de $f"
done
dit "$DIR/Mouflon-source.zip" "$P/LICENSE-MIT" "MIT License" \
    || rate "le code source n'a pas la licence MIT"
dit "$DIR/Mouflon-source.zip" "$P/LICENSE-APACHE" "Apache License" \
    || rate "le code source n'a pas la licence Apache"
unzip -p "$DIR/Mouflon-source.zip" "$P/Cargo.toml" | grep -x "version = \"$VERSION\"" > /dev/null \
    || rate "le code source n'est pas celui de la version $VERSION"
CHEMINS="$(sed "s#^$P/##" <<< "$CODE" | { grep -v '^$' || true; })"
# Markdown sous toutes ses écritures : .md, .MD, .markdown, .mdx.
ECRITS="$({ grep -iE '\.(md|markdown|mdx)$' <<< "$CHEMINS" || true; } | LC_ALL=C sort | tr '\n' ' ')"
[[ "$ECRITS" == "$MARKDOWN " ]] \
    || rate "les fichiers Markdown du code source devraient être « $MARKDOWN », et ce sont « ${ECRITS% } »"
! grep -E "^\.git/" <<< "$CHEMINS" > /dev/null || rate "le code source contient un dossier .git"
EN_TROP="$({ grep -E '(^|/)\.[^/]' <<< "$CHEMINS" || true; } | sed -E 's#^((.*/)?\.[^/]+).*#\1#' | LC_ALL=C sort -u \
    | { grep -vxF -f <(tr ' ' '\n' <<< "$CACHES") || true; } | tr '\n' ' ')"
[[ -z "$EN_TROP" ]] \
    || rate "les fichiers cachés du code source devraient être « $CACHES », et il a aussi « ${EN_TROP% } »"

# ── La liste de la version : signée par l'auteur, et juste ──────────────────
CLE="$(head -1 "$CLE_DE_L_AUTEUR" | cut -d' ' -f1,2)"
[[ "$CLE" == ssh-ed25519\ AAAA* ]] || rate "la clé de l'auteur ne se lit pas dans $CLE_DE_L_AUTEUR"
PERMIS="$(mktemp)"
trap 'rm -f "$PERMIS"' EXIT
echo "mouflon $CLE" > "$PERMIS"
ssh-keygen -Y verify -f "$PERMIS" -I mouflon -n mouflon -s "$DIR/$LISTE.sig" < "$DIR/$LISTE" > /dev/null 2>&1 \
    || rate "$LISTE n'est pas signé par la clé de l'auteur"
# Une seule ligne « version », celle de ce numéro ; une ligne « fichier <nom>
# <taille> <somme> » pour chacun des quatre fichiers, et pour eux seuls. (Une
# ligne d'un autre mot est permise : un Mouflon l'ignore.)
DITES="$(awk '$1 == "version"' "$DIR/$LISTE")"
[[ "$DITES" == "version $VERSION" ]] \
    || rate "$LISTE devrait dire « version $VERSION », et dit « ${DITES//$'\n'/ ; } »"
NOMMES="$(awk '$1 == "fichier" { print $2 }' "$DIR/$LISTE" | LC_ALL=C sort | tr '\n' ' ')"
[[ "$NOMMES" == "$PROGRAMMES " ]] || rate "$LISTE devrait nommer « $PROGRAMMES », et nomme « ${NOMMES% } »"
for f in $PROGRAMMES; do
    DIT="$(awk -v f="$f" '$1 == "fichier" && $2 == f { print $3, $4, NF }' "$DIR/$LISTE")"
    [[ "$DIT" == "$(stat -c %s "$DIR/$f") $(sha512sum "$DIR/$f" | cut -d' ' -f1) 4" ]] \
        || rate "$LISTE n'annonce pas la taille et la somme de $f"
done
# Le code de cette version porte la même clé : sinon les Mouflon qui en
# sortent ne sauraient lire aucune liste, et ne se mettraient plus à jour.
PORTEE="$({ unzip -p "$DIR/Mouflon-source.zip" "$P/crates/mouflon-app/assets/cle-de-signature.pub" 2> /dev/null || true; } \
    | head -1 | cut -d' ' -f1,2)"
[[ "$PORTEE" == "$CLE" ]] || rate "le code source ne porte pas la clé de l'auteur"

# ── L'app pour Mac : de cette version, signée, notarisée ────────────────────
MAC="$(unzip -Z1 "$DIR/Mouflon-macos-arm64.zip")" || rate "Mouflon-macos-arm64.zip ne se lit pas"
C="Mouflon.app/Contents"
for f in MacOS/mouflon Info.plist Resources/LICENSE-MIT Resources/LICENSE-APACHE Resources/CREDITS.md; do
    contient "$MAC" "$C/$f" || rate "l'app pour Mac n'a pas de $f"
done
unzip -p "$DIR/Mouflon-macos-arm64.zip" "$C/Info.plist" \
    | grep -A1 "<key>CFBundleShortVersionString</key>" | grep -F "<string>$VERSION</string>" > /dev/null \
    || rate "l'app pour Mac n'est pas la version $VERSION"
contient "$MAC" "$C/_CodeSignature/CodeResources" || rate "l'app pour Mac n'est pas signée"
# Le ticket de notarisation, agrafé par `stapler` : une app qui sort de la
# CI sans être passée par le Mac de l'auteur ne l'a pas.
contient "$MAC" "$C/CodeResources" || rate "l'app pour Mac n'est pas notarisée (pas de ticket agrafé)"

# ── Le dossier pour Windows, l'aperçu pour Linux ────────────────────────────
WINDOWS="$(unzip -Z1 "$DIR/Mouflon-windows-x64.zip" | tr '\\' '/')" || rate "Mouflon-windows-x64.zip ne se lit pas"
for f in Mouflon.exe LICENSE-MIT LICENSE-APACHE CREDITS.md; do
    contient "$WINDOWS" "Mouflon/$f" || rate "le dossier pour Windows n'a pas de $f"
done
LINUX="$(tar -tzf "$DIR/Mouflon-linux-x86_64.tar.gz")" || rate "Mouflon-linux-x86_64.tar.gz ne se lit pas"
for f in mouflon LICENSE-MIT LICENSE-APACHE CREDITS.md; do
    contient "$LINUX" "Mouflon/$f" || rate "l'aperçu pour Linux n'a pas de $f"
done

echo "✓ Mouflon $VERSION : les trois programmes, le code source et ses deux licences y sont, et leur liste est signée par l'auteur."
