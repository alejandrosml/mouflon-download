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

# Une clé d'essai, à la place de celle de l'auteur ; et une autre, qui n'est
# la clé de personne.
ssh-keygen -q -t ed25519 -N "" -C "" -f "$T/cle"
ssh-keygen -q -t ed25519 -N "" -C "" -f "$T/autre-cle"

# fabrique <dossier> : les sept fichiers d'une version $V sans défaut.
fabrique() {
    local d="$1" s="$T/atelier"
    rm -rf "$d" "$s"
    mkdir -p "$d" "$s/Mouflon-$V/docs" "$s/Mouflon-$V/crates/mouflon-app/assets" \
        "$s/Mouflon.app/Contents/MacOS" "$s/Mouflon.app/Contents/Resources" \
        "$s/Mouflon.app/Contents/_CodeSignature" "$s/win/Mouflon" "$s/linux/Mouflon"
    # Le code source.
    ( cd "$s/Mouflon-$V"
      echo "MIT License" > LICENSE-MIT; echo "Apache License" > LICENSE-APACHE
      printf '[workspace.package]\nversion = "%s"\n' "$V" > Cargo.toml
      mkdir -p .github/workflows
      cut -d' ' -f1,2 "$T/cle.pub" > crates/mouflon-app/assets/cle-de-signature.pub
      touch Cargo.lock README.md CREDITS.md docs/format.md docs/rig.md docs/sources.md docs/squelette.md crates/main.rs \
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

# emballe <dossier> : refait les quatre archives depuis l'atelier, les
# sommes, et la liste signée.
emballe() {
    local d="$1" s="$T/atelier"
    rm -f "$d"/Mouflon-*
    ( cd "$s" && zip -qr "$d/Mouflon-source.zip" "Mouflon-$V" && zip -qr "$d/Mouflon-macos-arm64.zip" Mouflon.app )
    ( cd "$s/win" && zip -qr "$d/Mouflon-windows-x64.zip" Mouflon )
    tar -C "$s/linux" -czf "$d/Mouflon-linux-x86_64.tar.gz" Mouflon
    sommes "$d"
}
sommes() {
    rm -f "$1/Mouflon-version.txt" "$1/Mouflon-version.txt.sig"
    ( cd "$1" && sha256sum Mouflon-* > SHA256SUMS )
    liste "$1"
}
# liste <dossier> [numéro] : écrit la liste de la version, et la signe.
liste() {
    ( cd "$1" && { echo "version ${2:-$V}"
        for f in Mouflon-macos-arm64.zip Mouflon-windows-x64.zip Mouflon-linux-x86_64.tar.gz Mouflon-source.zip; do
            if [[ -f "$f" ]]; then echo "fichier $f $(stat -c %s "$f") $(sha512sum "$f" | cut -d' ' -f1)"; fi
        done; } > Mouflon-version.txt )
    signe "$1"
}
# signe <dossier> [clé] : signe la liste telle qu'elle est.
signe() {
    rm -f "$1/Mouflon-version.txt.sig"
    ssh-keygen -q -Y sign -f "${2:-$T/cle}" -n mouflon "$1/Mouflon-version.txt" > /dev/null 2>&1
}

# attend <accepte|refuse> <ce qu'on essaie> [numéro] : lance le contrôle sur $T/version.
attend() {
    local voulu="$1" quoi="$2" numero="${3:-$V}" sortie
    if sortie="$(bash "$ICI/check-release.sh" "$T/version" "$numero" "$T/cle.pub" 2>&1)"; then
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

fabrique "$T/version"; rm "$T/version/Mouflon-version.txt"
attend refuse "sans la liste de la version"

fabrique "$T/version"; rm "$T/version/Mouflon-version.txt.sig"
attend refuse "une liste sans signature"

fabrique "$T/version"; sed -i "s/^version .*/version 9.9.10/" "$T/version/Mouflon-version.txt"
attend refuse "une liste retouchée après sa signature"

fabrique "$T/version"; signe "$T/version" "$T/autre-cle"
attend refuse "une liste signée par une autre clé que celle de l'auteur"

fabrique "$T/version"; liste "$T/version" 9.9.8
attend refuse "une liste bien signée, mais d'une autre version"

fabrique "$T/version"; echo "version 9.9.10" >> "$T/version/Mouflon-version.txt"; signe "$T/version"
attend refuse "une liste qui dit deux versions"

fabrique "$T/version"; sed -i "/^fichier Mouflon-windows/d" "$T/version/Mouflon-version.txt"; signe "$T/version"
attend refuse "une liste à laquelle il manque un fichier"

fabrique "$T/version"; sed -i -E "s/^(fichier Mouflon-linux[^ ]* [0-9]+ )[0-9a-f]{4}/\10000/" "$T/version/Mouflon-version.txt"; signe "$T/version"
attend refuse "une liste qui annonce une autre somme pour un fichier"

fabrique "$T/version"; sed -i -E "s/^(fichier Mouflon-source.zip )[0-9]+/\11/" "$T/version/Mouflon-version.txt"; signe "$T/version"
attend refuse "une liste qui annonce une autre taille pour un fichier"

fabrique "$T/version"; echo "fichier Mouflon-autre.zip 1 00" >> "$T/version/Mouflon-version.txt"; signe "$T/version"
attend refuse "une liste qui annonce un fichier de plus"

fabrique "$T/version"; echo "exige un systeme plus recent" >> "$T/version/Mouflon-version.txt"; signe "$T/version"
attend accepte "une liste avec une ligne d'un autre mot (un Mouflon l'ignore)"

# Ce qu'un Mouflon installé ne saurait pas lire ne passe pas non plus.
fabrique "$T/version"; rm "$T/version/Mouflon-version.txt.sig"
ssh-keygen -q -Y sign -O hashalg=sha256 -f "$T/cle" -n mouflon "$T/version/Mouflon-version.txt" > /dev/null 2>&1
attend refuse "une liste signée avec SHA-256 (un Mouflon n'accepte que SHA-512)"

fabrique "$T/version"; liste "$T/version" 9.9.1234567
attend refuse "un numéro de version trop long pour un Mouflon" 9.9.1234567

fabrique "$T/version"; printf '\fversion 9.9.10\n' >> "$T/version/Mouflon-version.txt"; signe "$T/version"
attend refuse "une seconde ligne « version » cachée derrière un caractère de contrôle"

fabrique "$T/version"; printf 'note d\351t\351\n' >> "$T/version/Mouflon-version.txt"; signe "$T/version"
attend refuse "une liste qui n'est pas du texte simple"

fabrique "$T/version"; sed -i 's/^version /version  /' "$T/version/Mouflon-version.txt"; signe "$T/version"
attend refuse "une ligne « version » avec une espace de trop"

fabrique "$T/version"; sed -i -E 's/^(fichier Mouflon-source.zip [0-9]+ )([0-9a-f]+)$/\1\U\2/' "$T/version/Mouflon-version.txt"; signe "$T/version"
attend refuse "une somme écrite en majuscules"

fabrique "$T/version"; for i in $(seq 1 1300); do echo "note $i 0123456789012345678901234567890123456789"; done >> "$T/version/Mouflon-version.txt"; signe "$T/version"
attend refuse "une liste de plus de 64 Kio"

fabrique "$T/version"; echo "AAAA" >> "$T/version/Mouflon-version.txt.sig"
attend refuse "une signature suivie d'autre chose"

fabrique "$T/version"; cat "$T/version/Mouflon-version.txt.sig" "$T/version/Mouflon-version.txt.sig" > "$T/deux"; mv "$T/deux" "$T/version/Mouflon-version.txt.sig"
attend refuse "deux signatures dans le même fichier"

fabrique "$T/version"; sed -i 's/^-----END SSH SIGNATURE-----$/-----END SSH SIGNATURE----- et la suite/' "$T/version/Mouflon-version.txt.sig"
attend refuse "une signature dont la dernière ligne dit autre chose"

fabrique "$T/version"; printf '# plus livres\nvieux.dll\npets/pelote\n\n' > "$A/win/Mouflon/a-retirer.txt"; cp "$A/win/Mouflon/a-retirer.txt" "$A/linux/Mouflon/"; emballe "$T/version"
attend accepte "une version qui retire un fichier et un animal"

for ligne in "../notes.txt" "C:notes.txt" "pets/../x" "Mouflon.exe" "PETS" "pets" "x." "LICENSE-MIT"; do
    fabrique "$T/version"; echo "$ligne" > "$A/win/Mouflon/a-retirer.txt"; emballe "$T/version"
    attend refuse "une version qui voudrait retirer « $ligne » (Windows)"
done
fabrique "$T/version"; echo "mouflon" > "$A/linux/Mouflon/a-retirer.txt"; emballe "$T/version"
attend refuse "une version qui voudrait retirer le programme (Linux)"
rm -f "$A/win/Mouflon/a-retirer.txt" "$A/linux/Mouflon/a-retirer.txt"

fabrique "$T/version"; echo "lit MOUFLON_ESSAI_SOURCE" > "$A/linux/Mouflon/mouflon"; emballe "$T/version"
attend refuse "un programme d'essai pour Linux"

fabrique "$T/version"; echo "lit MOUFLON_ESSAI_SOURCE" > "$A/win/Mouflon/Mouflon.exe"; emballe "$T/version"
attend refuse "un programme d'essai pour Windows"

fabrique "$T/version"; echo "lit MOUFLON_ESSAI_SOURCE" > "$A/Mouflon.app/Contents/MacOS/mouflon"; emballe "$T/version"
attend refuse "un programme d'essai pour Mac"

fabrique "$T/version"; cut -d' ' -f1,2 "$T/autre-cle.pub" > "$A/Mouflon-$V/crates/mouflon-app/assets/cle-de-signature.pub"; emballe "$T/version"
attend refuse "un code source qui porte une autre clé"

fabrique "$T/version"; rm "$A/Mouflon-$V/crates/mouflon-app/assets/cle-de-signature.pub"; emballe "$T/version"
attend refuse "un code source qui ne porte pas de clé"

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
