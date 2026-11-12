#!/usr/bin/env bash
# L'essai du contrôle : fabrique une fausse version complète, que
# scripts/check-release.sh doit accepter, puis la même avec un défaut à
# chaque fois, qu'il doit refuser.
#
#   bash scripts/test-check-release.sh
set -euo pipefail

ICI="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
V=9.9.9
RATES=0

# fabrique <dossier> : les cinq fichiers d'une version $V sans défaut.
fabrique() {
    local d="$1" s="$T/atelier"
    rm -rf "$d" "$s"
    mkdir -p "$d" "$s/Mouflon-$V/docs" "$s/Mouflon-$V/crates" \
        "$s/Mouflon.app/Contents/MacOS" "$s/Mouflon.app/Contents/Resources" \
        "$s/Mouflon.app/Contents/_CodeSignature" "$s/win/Mouflon" "$s/linux/Mouflon"
    # Le code source.
    ( cd "$s/Mouflon-$V"
      echo "MIT License" > LICENSE-MIT; echo "Apache License" > LICENSE-APACHE
      printf '[workspace.package]\nversion = "%s"\n' "$V" > Cargo.toml
      mkdir -p .github/workflows
      touch Cargo.lock README.md CREDITS.md docs/format.md docs/rig.md docs/squelette.md crates/main.rs \
          .gitattributes .gitignore .github/workflows/ci.yml )
    # L'app pour Mac, signée et notarisée.
    ( cd "$s/Mouflon.app/Contents"
      printf '<key>CFBundleShortVersionString</key>\n<string>%s</string>\n' "$V" > Info.plist
      touch MacOS/mouflon _CodeSignature/CodeResources CodeResources \
          Resources/LICENSE-MIT Resources/LICENSE-APACHE Resources/CREDITS.md )
    touch "$s/win/Mouflon/Mouflon.exe" "$s/win/Mouflon/LICENSE-MIT" "$s/win/Mouflon/LICENSE-APACHE" "$s/win/Mouflon/CREDITS.md"
    touch "$s/linux/Mouflon/mouflon" "$s/linux/Mouflon/LICENSE-MIT" "$s/linux/Mouflon/LICENSE-APACHE" "$s/linux/Mouflon/CREDITS.md"
    emballe "$d"
}

# emballe <dossier> : refait les quatre archives depuis l'atelier, et les sommes.
emballe() {
    local d="$1" s="$T/atelier"
    rm -f "$d"/Mouflon-*
    ( cd "$s" && zip -qr "$d/Mouflon-source.zip" "Mouflon-$V" && zip -qr "$d/Mouflon-macos-arm64.zip" Mouflon.app )
    ( cd "$s/win" && zip -qr "$d/Mouflon-windows-x64.zip" Mouflon )
    tar -C "$s/linux" -czf "$d/Mouflon-linux-x86_64.tar.gz" Mouflon
    sommes "$d"
}
sommes() { ( cd "$1" && sha256sum Mouflon-* > SHA256SUMS ); }

# attend <accepte|refuse> <ce qu'on essaie> [numéro] : lance le contrôle sur $T/version.
attend() {
    local voulu="$1" quoi="$2" numero="${3:-$V}" sortie
    if sortie="$(bash "$ICI/check-release.sh" "$T/version" "$numero" 2>&1)"; then
        obtenu=accepte
    else
        obtenu=refuse
    fi
    if [[ "$obtenu" == "$voulu" ]]; then
        echo "✓ $quoi : ${sortie##*$'\n'}"
    else
        echo "✗ $quoi : devait être « $voulu », a été « $obtenu »"; echo "$sortie" | sed 's/^/    /'
        RATES=$((RATES + 1))
    fi
}
A="$T/atelier"

fabrique "$T/version"
attend accepte "une version complète"
attend refuse "le numéro d'une autre version" 9.9.8
attend refuse "un numéro qui n'en est pas un" "9.9"

fabrique "$T/version"; rm "$T/version/Mouflon-source.zip"; sommes "$T/version"
attend refuse "sans l'archive du code"

fabrique "$T/version"; rm "$A/Mouflon-$V/LICENSE-APACHE"; emballe "$T/version"
attend refuse "un code source sans la licence Apache"

fabrique "$T/version"; echo "autre chose" > "$A/Mouflon-$V/LICENSE-MIT"; emballe "$T/version"
attend refuse "un code source dont la licence MIT n'en est pas une"

fabrique "$T/version"; printf 'version = "9.9.8"\n' > "$A/Mouflon-$V/Cargo.toml"; emballe "$T/version"
attend refuse "le code source d'une autre version"

fabrique "$T/version"; touch "$A/Mouflon-$V/NOTES.md"; emballe "$T/version"
attend refuse "un code source avec un fichier Markdown de plus"

fabrique "$T/version"; mkdir "$A/Mouflon-$V/docs/suite"; touch "$A/Mouflon-$V/docs/suite/plan.md"; emballe "$T/version"
attend refuse "un code source avec un fichier Markdown de plus, dans un dossier"

fabrique "$T/version"; touch "$A/Mouflon-$V/crates/NOTES.MD"; emballe "$T/version"
attend refuse "un fichier Markdown de plus, en majuscules"

fabrique "$T/version"; touch "$A/Mouflon-$V/docs/plan.markdown"; emballe "$T/version"
attend refuse "un fichier Markdown de plus, écrit .markdown"

fabrique "$T/version"; mkdir "$A/Mouflon-$V/crates/.reglages"; touch "$A/Mouflon-$V/crates/.reglages/local.json"; emballe "$T/version"
attend refuse "un code source avec un dossier caché de plus"

fabrique "$T/version"; touch "$A/Mouflon-$V/.env"; emballe "$T/version"
attend refuse "un code source avec un fichier caché de plus"

fabrique "$T/version"; rm "$A/Mouflon-$V/docs/rig.md"; emballe "$T/version"
attend refuse "un code source sans un de ses modes d'emploi"

fabrique "$T/version"; mkdir "$A/Mouflon-$V/.git"; touch "$A/Mouflon-$V/.git/HEAD"; emballe "$T/version"
attend refuse "un code source avec son dossier .git"

fabrique "$T/version"; rm "$A/Mouflon.app/Contents/CodeResources"; emballe "$T/version"
attend refuse "une app pour Mac qui n'est pas notarisée"

fabrique "$T/version"; rm -r "$A/Mouflon.app/Contents/_CodeSignature"; emballe "$T/version"
attend refuse "une app pour Mac qui n'est pas signée"

fabrique "$T/version"; printf '<key>CFBundleShortVersionString</key>\n<string>9.9.8</string>\n' > "$A/Mouflon.app/Contents/Info.plist"; emballe "$T/version"
attend refuse "l'app pour Mac d'une autre version"

fabrique "$T/version"; rm "$A/win/Mouflon/Mouflon.exe"; emballe "$T/version"
attend refuse "un dossier pour Windows sans Mouflon.exe"

fabrique "$T/version"; rm "$A/linux/Mouflon/LICENSE-MIT"; emballe "$T/version"
attend refuse "un aperçu pour Linux sans la licence MIT"

fabrique "$T/version"; echo "en trop" >> "$T/version/Mouflon-windows-x64.zip"
attend refuse "un fichier changé après le calcul des sommes"

fabrique "$T/version"; rm "$T/version/SHA256SUMS"
attend refuse "sans les sommes de contrôle"

fabrique "$T/version"; touch "$T/version/Mouflon-1.0.3-macos-arm64.zip"
attend refuse "avec un fichier en trop"

if [[ "$RATES" -gt 0 ]]; then
    echo "✗ $RATES essai(s) manqué(s)"; exit 1
fi
echo "✓ le contrôle accepte ce qu'il doit accepter et refuse le reste"
