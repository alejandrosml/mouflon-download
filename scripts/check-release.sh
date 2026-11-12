#!/usr/bin/env bash
# Contrôle les fichiers d'une version de Mouflon, avant qu'elle reste publiée
# ici :
#
#   bash scripts/check-release.sh <dossier des fichiers> <numéro, comme 1.0.4>
#
# Une version, ce sont cinq fichiers, aux noms fixes (la page de présentation
# pointe sur …/releases/latest/download/<nom>) :
#
#   Mouflon-macos-arm64.zip        l'app pour Mac, signée et notarisée
#   Mouflon-windows-x64.zip        le dossier pour Windows
#   Mouflon-linux-x86_64.tar.gz    l'aperçu pour Linux
#   Mouflon-source.zip             le code source de cette version
#   SHA256SUMS                     les sommes de contrôle des quatre autres
#
# Mouflon est open source par ses versions : sans l'archive du code de cette
# version-là, avec ses deux licences, rien ne reste publié.
set -euo pipefail

DIR="${1:?le dossier des fichiers de la version}"
VERSION="${2:?le numéro de la version, comme 1.0.4}"
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

# ── Les cinq fichiers, et rien d'autre ──────────────────────────────────────
TROUVES="$(ls -A "$DIR" | LC_ALL=C sort | tr '\n' ' ')"
[[ "$TROUVES" == "$PROGRAMMES SHA256SUMS " ]] \
    || rate "la version devrait avoir « $PROGRAMMES SHA256SUMS », et elle a « ${TROUVES% } »"

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

echo "✓ Mouflon $VERSION : les trois programmes, le code source et ses deux licences y sont."
