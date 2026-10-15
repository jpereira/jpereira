#!/usr/bin/env bash
# Atualiza o README.md: regenera a tabela de projetos (descrição, linguagem,
# stars/forks) a partir da API do GitHub.
#
# Uso: ./update.sh [--commit] [--push]
#   --commit  faz commit do README.md se houver mudanças
#   --push    commit + git push
set -euo pipefail

USER_GH="jpereira"
README="$(cd "$(dirname "$0")" && pwd)/README.md"
START="<!-- PROJECTS:START -->"
END="<!-- PROJECTS:END -->"

# Ordem de exibição (nome do repo, 2 por linha)
REPOS=(
  softgre zapbot getright libclosedcaption php-dhcpdleases freeradius-server
  dotfiles libinjection libkqueue mod_auth_radius BitcoinChecker nginx-backtrace-ng
  isc-dhp-relay
)

DO_COMMIT=0; DO_PUSH=0
for a in "$@"; do
  case "$a" in
    --commit) DO_COMMIT=1 ;;
    --push)   DO_COMMIT=1; DO_PUSH=1 ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) echo "opção inválida: $a" >&2; exit 1 ;;
  esac
done

for c in jq curl; do command -v "$c" >/dev/null || { echo "falta: $c" >&2; exit 1; }; done
grep -q "$START" "$README" && grep -q "$END" "$README" \
  || { echo "marcadores $START/$END não encontrados em $README" >&2; exit 1; }

api() { # usa gh se disponível (sem rate limit), senão curl
  if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
    gh api "$1"
  else
    curl -fsSL ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} "https://api.github.com/$1"
  fi
}

lang_color() {
  case "$1" in
    C) echo 555555 ;; "C++") echo f34b7d ;; PHP) echo 4F5D95 ;; JavaScript) echo f1e05a ;;
    Python) echo 3572A5 ;; Shell) echo 89e051 ;; Kotlin) echo A97BFF ;;
    "Vim Script"|"Vim script") echo 199f4b ;; Swift) echo F05138 ;; *) echo 8b949e ;;
  esac
}
badge_escape() { echo "$1" | sed 's/-/--/g; s/_/__/g; s/ /%20/g; s/+/%2B/g'; }
html_escape() { echo "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }

card() { # $1=repo
  local r="$1" j desc lang fork color kind
  j=$(api "repos/$USER_GH/$r") || { echo "aviso: falha em $r" >&2; return 0; }
  desc=$(html_escape "$(jq -r '.description // ""' <<<"$j")")
  lang=$(jq -r '.language // ""' <<<"$j")
  fork=$(jq -r '.fork' <<<"$j")
  kind="Public"; [ "$fork" = true ] && kind="Fork"
  cat <<CARD
    <td width="50%" valign="top">
      <b><a href="https://github.com/$USER_GH/$r">$r</a></b>
      <a href="https://github.com/$USER_GH/$r"><img height="18" src="https://img.shields.io/badge/-$kind-lightgrey?style=flat-square" alt="$kind"/></a><br/>
      <sub>$desc</sub><br/>
CARD
  if [ -n "$lang" ]; then
    color=$(lang_color "$lang")
    echo "      <img height=\"18\" src=\"https://img.shields.io/badge/-$(badge_escape "$lang")-$color?style=flat-square\" alt=\"$lang\"/>"
  fi
  cat <<CARD
      <a href="https://github.com/$USER_GH/$r/stargazers"><img height="18" src="https://img.shields.io/github/stars/$USER_GH/$r?style=social" alt="stars"/></a>
      <a href="https://github.com/$USER_GH/$r/forks"><img height="18" src="https://img.shields.io/github/forks/$USER_GH/$r?style=social" alt="forks"/></a>
    </td>
CARD
}

TABLE=$(mktemp); trap 'rm -f "$TABLE" "$TABLE.new"' EXIT
{
  echo "<table>"
  i=0
  for r in "${REPOS[@]}"; do
    [ $((i % 2)) -eq 0 ] && echo "  <tr>"
    card "$r"
    [ $((i % 2)) -eq 1 ] && echo "  </tr>"
    i=$((i + 1))
  done
  if [ $((i % 2)) -eq 1 ]; then echo '    <td width="50%"></td>'; echo "  </tr>"; fi
  echo "</table>"
} > "$TABLE"

# Troca o conteúdo entre os marcadores
awk -v s="$START" -v e="$END" -v f="$TABLE" '
  $0==s { print; while ((getline l < f) > 0) print l; skip=1; next }
  $0==e { skip=0 }
  !skip { print }
' "$README" > "$TABLE.new"

# Atualiza o total de stars (soma dos repos listados)
TOTAL=0
for r in "${REPOS[@]}"; do
  n=$(api "repos/$USER_GH/$r" 2>/dev/null | jq -r '.stargazers_count // 0') || n=0
  TOTAL=$((TOTAL + n))
done
sed -E "s#badge/stars-[0-9]+-#badge/stars-$TOTAL-#" "$TABLE.new" > "$README"

echo "README.md atualizado ($TOTAL stars nos projetos listados)."

if [ "$DO_COMMIT" -eq 1 ]; then
  cd "$(dirname "$README")"
  if git diff --quiet -- README.md; then echo "sem mudanças."; else
    git add README.md && git commit -m "Atualiza README"
    [ "$DO_PUSH" -eq 1 ] && git push
  fi
fi
