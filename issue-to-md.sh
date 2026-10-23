#!/usr/bin/env bash
# Converte issue.json + comments.json (github/gitlab/onedev) em issue.md e comments.md para contexto de agente.
# Uso: issue-to-md.sh [dir ...]   (padrão: ./issue/*/ ; ou um dir com issue.json direto)
#      A saída vai para <dir>/issue.md e <dir>/comments.md
set -euo pipefail

command -v jq >/dev/null || { echo "jq não encontrado" >&2; exit 1; }

detect() { # $1=issue.json
  jq -r 'if has("iid") then "gitlab"
         elif has("submitter") then "onedev"
         elif has("createdAt") then "github"
         else "unknown" end' "$1"
}

render_gitlab() { # $1=issue.json $2=comments.json $3=issue.md $4=comments.md
  # uploads baixados pelo entrypoint em <dir>/img/<secret8>_<arquivo>: reescreve as referências para o caminho local
  local imgdir; imgdir="$(cd "$(dirname "$1")" && pwd)/img"
  [[ -d $imgdir ]] || imgdir=""
  jq -r --arg imgdir "$imgdir" '
    def fix: if $imgdir == "" then . else gsub("/uploads/(?<s>[0-9a-f]{32})/(?<f>[^)\\s]+)"; "\($imgdir)/\(.s[0:8])_\(.f)") end;
    "# #\(.iid) \(.title)\n",
    "- Plataforma: GitLab",
    "- Estado: \(.state)",
    "- Autor: \(.author.name) (@\(.author.username))",
    "- Criada: \(.created_at)  |  Atualizada: \(.updated_at)",
    (if .closed_at then "- Fechada: \(.closed_at)" else empty end),
    "- Labels: \(if (.labels|length)>0 then (.labels|join(", ")) else "-" end)",
    "- Assignees: \(if (.assignees|length)>0 then ([.assignees[].username]|join(", ")) else "-" end)",
    (if .milestone then "- Milestone: \(.milestone.title)" else empty end),
    (if .due_date then "- Prazo: \(.due_date)" else empty end),
    "- URL: \(.web_url)",
    "\n## Descrição\n",
    ((.description // "_(sem descrição)_") | fix)
  ' "$1" > "$3"
  jq -r --arg imgdir "$imgdir" '
    def fix: if $imgdir == "" then . else gsub("/uploads/(?<s>[0-9a-f]{32})/(?<f>[^)\\s]+)"; "\($imgdir)/\(.s[0:8])_\(.f)") end;
    [ .[] | select(.system|not) ] | sort_by(.created_at) as $c
    | "# Comentários (\($c|length))\n",
      ($c[] | "## \(.author.name) (@\(.author.username)) em \(.created_at)\(if .internal then " [interno]" else "" end)\n\n\(.body | fix)\n")
  ' "$2" > "$4"
  if [[ -n $imgdir ]] && compgen -G "$imgdir/*" >/dev/null; then
    { echo; echo "## Imagens anexas"; echo; printf -- '- %s\n' "$imgdir"/*; } >> "$3"
  fi
}

render_onedev() {
  # anexos baixados pelo entrypoint em <dir>/img/<uuid8>_<arquivo>: reescreve as referências para o caminho local
  local imgdir; imgdir="$(cd "$(dirname "$1")" && pwd)/img"
  [[ -d $imgdir ]] || imgdir=""
  jq -r --arg imgdir "$imgdir" '
    def fix: if $imgdir == "" then . else gsub("/~downloads/projects/[0-9]+/attachments/(?<s>[0-9a-f-]{36})/(?<f>[^)\\s?]+)(\\?v=[0-9]+)?"; "\($imgdir)/\(.s[0:8])_\(.f)") end;
    "# \(.reference) \(.title)\n",
    "- Plataforma: OneDev",
    "- Estado: \(.state)",
    "- Autor: \(.submitter)",
    "- Criada: \(.submitDate)  |  Última atividade: \(.lastActivityDate)",
    "- Projeto: \(.Project)",
    (["Type","Priority","Assignees","Build"][] as $k
       | select((.[$k]|type)=="array" and (.[$k]|length)>0)
       | "- \($k): \(.[$k]|join(", "))"),
    (if .branch then "- Branch: \(.branch)" else empty end),
    "- URL: \(.link)",
    "\n## Descrição\n",
    ((.description // "_(sem descrição)_") | fix)
  ' "$1" > "$3"
  jq -r --arg imgdir "$imgdir" '
    def fix: if $imgdir == "" then . else gsub("/~downloads/projects/[0-9]+/attachments/(?<s>[0-9a-f-]{36})/(?<f>[^)\\s?]+)(\\?v=[0-9]+)?"; "\($imgdir)/\(.s[0:8])_\(.f)") end;
    sort_by(.date) as $c
    | "# Comentários (\($c|length))\n",
      ($c[] | "## \(.user) em \(.date)\n\n\(.content | fix)\n")
  ' "$2" > "$4"
  if [[ -n $imgdir ]] && compgen -G "$imgdir/*" >/dev/null; then
    { echo; echo "## Imagens anexas"; echo; printf -- '- %s\n' "$imgdir"/*; } >> "$3"
  fi
}

render_github() {
  # uploads baixados pelo entrypoint em <dir>/img/<uuid>.<ext>: reescreve as referências para o caminho local
  local imgdir map='{}' f b; imgdir="$(cd "$(dirname "$1")" && pwd)/img"
  [[ -d $imgdir ]] || imgdir=""
  if [[ -n $imgdir ]]; then
    for f in "$imgdir"/*; do
      [[ -f $f ]] || continue
      b=${f##*/}; map=$(jq -c --arg k "${b%%.*}" --arg v "$f" '. + {($k): $v}' <<<"$map")
    done
  fi
  jq -r --argjson map "$map" '
    def fix: gsub("https://github\\.com/user-attachments/assets/(?<u>[0-9a-f-]{36})"; .u as $u | $map[$u] // "https://github.com/user-attachments/assets/\($u)");
    "# #\(.number) \(.title)\n",
    "- Plataforma: GitHub",
    "- Estado: \(.state)",
    "- Autor: \(.author.name // .author.login) (@\(.author.login))",
    "- Criada: \(.createdAt)  |  Atualizada: \(.updatedAt)",
    "- Labels: \(if (.labels|length)>0 then ([.labels[].name]|join(", ")) else "-" end)",
    "- Assignees: \(if (.assignees|length)>0 then ([.assignees[].login]|join(", ")) else "-" end)",
    (if .milestone then "- Milestone: \(.milestone.title)" else empty end),
    "- URL: \(.url)",
    "\n## Descrição\n",
    (if (.body // "") == "" then "_(sem descrição)_" else (.body | fix) end)
  ' "$1" > "$3"
  jq -r --argjson map "$map" '
    def fix: gsub("https://github\\.com/user-attachments/assets/(?<u>[0-9a-f-]{36})"; .u as $u | $map[$u] // "https://github.com/user-attachments/assets/\($u)");
    [ .[] | select(.isMinimized|not) ] | sort_by(.createdAt) as $c
    | "# Comentários (\($c|length))\n",
      ($c[] | "## @\(.author.login) em \(.createdAt)\n\n\(.body | fix)\n")
  ' "$2" > "$4"
  if [[ -n $imgdir ]] && compgen -G "$imgdir/*" >/dev/null; then
    { echo; echo "## Imagens anexas"; echo; printf -- '- %s\n' "$imgdir"/*; } >> "$3"
  fi
}

convert() { # $1=dir
  local d=${1%/} tmp="" kind issue comments
  issue="$d/issue.json"; comments="$d/comments.json"
  [[ -s $issue ]] || { echo "pulando $d: sem issue.json" >&2; return 0; }
  if [[ ! -s $comments ]]; then
    tmp=$(mktemp); echo '[]' > "$tmp"; comments=$tmp
  fi
  kind=$(detect "$issue")
  [[ $kind != unknown ]] || { echo "pulando $d: formato não reconhecido" >&2; rm -f "$tmp"; return 0; }
  "render_$kind" "$issue" "$comments" "$d/issue.md" "$d/comments.md"
  [[ -z $tmp ]] || rm -f "$tmp"
  echo "gerado $d/issue.md e $d/comments.md ($kind)"
}

if [[ $# -eq 0 ]]; then
  base="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/issue"
  if [[ -f $base/issue.json ]]; then set -- "$base"; else set -- "$base"/*/; fi
fi
for d in "$@"; do convert "$d"; done
