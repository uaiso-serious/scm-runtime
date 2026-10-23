#!/bin/bash
set -euo pipefail

: "${GIT_SERVER_TYPE:?GIT_SERVER_TYPE obrigatório (onedev, gitlab ou github)}"
: "${GIT_REPO_URL:?GIT_REPO_URL obrigatório}"
: "${GIT_TOKEN:?GIT_TOKEN obrigatório}"
: "${GIT_BASE_BRANCH:?GIT_BASE_BRANCH obrigatório}"
: "${GIT_USER_NAME:?GIT_USER_NAME obrigatório}"
: "${GIT_USER_EMAIL:?GIT_USER_EMAIL obrigatório}"

GIT_SERVER_TYPE="${GIT_SERVER_TYPE,,}"
case "$GIT_SERVER_TYPE" in
  onedev|gitlab|github)
    export GIT_SERVER_TYPE
    ;;
  *)
    echo "GIT_SERVER_TYPE inválido: '$GIT_SERVER_TYPE' (valores aceitos: onedev, gitlab, github)" >&2
    exit 1
    ;;
esac

# ISSUE_ID, quando presente, sobrescreve GIT_BRANCH
if [[ -n "${ISSUE_ID:-}" ]]; then
  GIT_BRANCH="issue/${ISSUE_ID}"
fi
: "${GIT_BRANCH:?GIT_BRANCH ou ISSUE_ID obrigatório}"

# modo autônomo (não interativo) só faz sentido com uma issue para trabalhar
if [[ "${AUTONOMOUS_MODE:-false}" == "true" && -z "${ISSUE_ID:-}" ]]; then
  echo "AUTONOMOUS_MODE=true exige ISSUE_ID definido" >&2
  exit 1
fi

git config --global user.name "$GIT_USER_NAME"
git config --global user.email "$GIT_USER_EMAIL"
git config --global push.autoSetupRemote true
# o token fica só no ambiente, nunca em disco
git config --global credential.helper \
  '!f() { echo "username=${GIT_USERNAME:-git}"; echo "password=$GIT_TOKEN"; }; f'

if [[ -n "${GIT_CO_AUTHOR:-}" ]]; then
  HOOKS_DIR="$HOME/.config/git/hooks"
  mkdir -p "$HOOKS_DIR"
  cat > "$HOOKS_DIR/prepare-commit-msg" <<'EOF'
#!/bin/bash
set -euo pipefail

CO_AUTHOR="${GIT_CO_AUTHOR:-$(git config --get user.coAuthor || true)}"
if [[ -n "$CO_AUTHOR" ]]; then
  git interpret-trailers --in-place --if-exists addIfDifferent \
    --trailer "Co-authored-by: $CO_AUTHOR" "$1"
fi
EOF
  chmod +x "$HOOKS_DIR/prepare-commit-msg"
  git config --global user.coAuthor "$GIT_CO_AUTHOR"
  git config --global core.hooksPath "$HOOKS_DIR"
fi

if [[ "$GIT_REPO_URL" =~ ^((https?)://([^/]+)) ]]; then
  GIT_SERVER_URL="${BASH_REMATCH[1]}"
  GIT_SERVER_PROTOCOL="${BASH_REMATCH[2]}"
  GIT_SERVER_HOST="${BASH_REMATCH[3]}"
else
  GIT_SERVER_URL="${GIT_REPO_URL%/*}"
  GIT_SERVER_PROTOCOL="${GIT_SERVER_URL%%://*}"
  GIT_SERVER_HOST="${GIT_SERVER_URL#*://}"
fi
# caminho do projeto (grupo/projeto ou owner/repo), sem .git
REPO_PATH="${GIT_REPO_URL#"$GIT_SERVER_URL"/}"
REPO_PATH="${REPO_PATH%.git}"
REPO_PATH="${REPO_PATH%/}"
export GIT_SERVER_URL GIT_SERVER_PROTOCOL GIT_SERVER_HOST REPO_PATH GIT_REPO_URL GIT_BASE_BRANCH GIT_BRANCH

case "$GIT_SERVER_TYPE" in
  onedev)
    tod config set server-url "$GIT_SERVER_URL"
    tod config set access-token "$GIT_TOKEN"
    ;;
  gitlab)
    export GITLAB_HOST="${GITLAB_HOST:-$GIT_SERVER_URL}"
    export GITLAB_TOKEN="${GITLAB_TOKEN:-$GIT_TOKEN}"
    glab config set api_protocol "$GIT_SERVER_PROTOCOL" --host "$GIT_SERVER_HOST" >/dev/null 2>&1 \
      || echo "AVISO: falha ao definir api_protocol=$GIT_SERVER_PROTOCOL no glab para $GIT_SERVER_HOST" >&2
    echo "glab configurado para $GITLAB_HOST (api_protocol=$GIT_SERVER_PROTOCOL)"
    ;;
  github)
    export GH_HOST="${GH_HOST:-$GIT_SERVER_HOST}"
    export GH_TOKEN="${GH_TOKEN:-$GIT_TOKEN}"
    if [[ "$GH_HOST" != "github.com" ]]; then
      export GH_ENTERPRISE_TOKEN="${GH_ENTERPRISE_TOKEN:-$GIT_TOKEN}"
    fi
    echo "gh configurado para $GH_HOST"
    ;;
esac

mkdir -p /tmp/repo
TEMPLATES_DIR="${SCM_TEMPLATES_DIR:-/usr/local/share/scm-runtime/templates}"
render() { ISSUE_REF="${ISSUE_ID:-<ISSUE_ID>}" perl -pe 's/\$\{([A-Z0-9_]+)\}/$ENV{$1} \/\/ ""/ge' "$1" > "$2"; }
# repo.md: informações do repositório; cli.md: exemplos de uso da CLI da forja (opcional para quem tem MCP)
render "$TEMPLATES_DIR/${GIT_SERVER_TYPE}.md" /tmp/repo/repo.md
render "$TEMPLATES_DIR/cli/${GIT_SERVER_TYPE}.md" /tmp/repo/cli.md

# só clona se /workspace estiver vazio (pode ser um volume externo já populado)
mkdir -p /workspace
if [[ -z "$(ls -A /workspace)" ]]; then
  git clone --branch "$GIT_BASE_BRANCH" "$GIT_REPO_URL" /workspace
  cd /workspace
else
  echo "AVISO: /workspace não está vazio, clone ignorado" >&2
  cd /workspace
fi

# ls-remote --exit-code: 0 = existe, 2 = não existe; outro código = erro (rede/credencial), não confundir com "não existe"
REMOTE_RC=0
git ls-remote --exit-code --heads origin "$GIT_BRANCH" >/dev/null 2>&1 || REMOTE_RC=$?

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "AVISO: /workspace não é um repositório git, checkout da branch ignorado" >&2
elif [[ "$REMOTE_RC" -ne 0 && "$REMOTE_RC" -ne 2 ]]; then
  echo "ERRO: falha ao consultar a branch $GIT_BRANCH em origin (código $REMOTE_RC)" >&2
  exit 1
elif [[ "$REMOTE_RC" -eq 0 ]]; then
  git fetch origin "$GIT_BRANCH" \
    || { echo "ERRO: falha ao buscar origin/$GIT_BRANCH" >&2; exit 1; }
  # commits locais fora do remoto seriam perdidos pelo checkout -B: aborta
  if git show-ref --verify --quiet "refs/heads/$GIT_BRANCH" \
     && [[ -n "$(git rev-list "refs/heads/$GIT_BRANCH" --not "origin/$GIT_BRANCH" | head -n1)" ]]; then
    echo "ERRO: a branch local '$GIT_BRANCH' tem commits que não estão em origin/$GIT_BRANCH (divergente/à frente); faça push ou resolva antes de iniciar" >&2
    exit 1
  fi
  git checkout -B "$GIT_BRANCH" "origin/$GIT_BRANCH"
elif git show-ref --verify --quiet "refs/heads/$GIT_BRANCH"; then
  # branch só local (ex.: execução anterior no mesmo workspace): reaproveita
  git checkout "$GIT_BRANCH"
else
  git checkout -b "$GIT_BRANCH"
fi

# falha no contexto da issue: aborta em modo autônomo (sem humano para perceber), senão só avisa
issue_fail() {
  if [[ "${AUTONOMOUS_MODE:-false}" == "true" ]]; then
    echo "ERRO: $1" >&2
    exit 1
  fi
  echo "AVISO: $1" >&2
}

if [[ -n "${ISSUE_ID:-}" ]]; then
  mkdir -p /tmp/issue
  case "$GIT_SERVER_TYPE" in
    onedev)
      if [[ "${AUTONOMOUS_MODE:-false}" == "true" ]]; then
        # TODO implementar react na issue com o emoji eyes
        :
      fi
      tod issue get "$ISSUE_ID" > /tmp/issue/issue.json \
        || issue_fail "falha ao baixar a issue #$ISSUE_ID para /tmp/issue/issue.json"
      tod issue get-comments "$ISSUE_ID" > /tmp/issue/comments.json \
        || issue_fail "falha ao baixar comentários da issue #$ISSUE_ID para /tmp/issue/comments.json"
      ;;
    gitlab)
      if [[ "${AUTONOMOUS_MODE:-false}" == "true" ]]; then
        # TODO implementar react na issue com o emoji eyes
        :
      fi
      GL_PROJECT="${REPO_PATH//\//%2F}"
      glab api "projects/$GL_PROJECT/issues/$ISSUE_ID" > /tmp/issue/issue.json \
        || issue_fail "falha ao baixar a issue #$ISSUE_ID para /tmp/issue/issue.json"
      # TODO --paginate concatena arrays JSON (um por página); juntar com jq -s 'add' quando houver >1 página
      glab api --paginate "projects/$GL_PROJECT/issues/$ISSUE_ID/notes" > /tmp/issue/comments.json \
        || issue_fail "falha ao baixar comentários da issue #$ISSUE_ID para /tmp/issue/comments.json"
      ;;
    github)
      if [[ "${AUTONOMOUS_MODE:-false}" == "true" ]]; then
        # TODO implementar react na issue com o emoji eyes
        :
      fi
      gh issue view "$ISSUE_ID" -R "$GH_HOST/$REPO_PATH" \
        --json number,title,body,state,author,labels,assignees,milestone,createdAt,updatedAt,url \
        > /tmp/issue/issue.json \
        || issue_fail "falha ao baixar a issue #$ISSUE_ID para /tmp/issue/issue.json"
      gh issue view "$ISSUE_ID" -R "$GH_HOST/$REPO_PATH" --json comments --jq '.comments' \
        > /tmp/issue/comments.json \
        || issue_fail "falha ao baixar comentários da issue #$ISSUE_ID para /tmp/issue/comments.json"
      ;;
  esac
  jq -e 'type == "object" and length > 0' /tmp/issue/issue.json >/dev/null 2>&1 \
    || issue_fail "issue.json da issue #$ISSUE_ID vazio ou inválido"
  # comentários são opcionais: arquivo vazio ou [] é válido; só falha se houver conteúdo que não seja array
  if [[ -s /tmp/issue/comments.json ]]; then
    jq -e 'type == "array"' /tmp/issue/comments.json >/dev/null 2>&1 \
      || issue_fail "comments.json da issue #$ISSUE_ID inválido"
  fi
  if [[ "$GIT_SERVER_TYPE" == "gitlab" ]]; then
    # imagens anexas (/uploads/<secret>/<arquivo>) da descrição e dos comentários -> /tmp/issue/img/<secret8>_<arquivo>
    # o issue-to-md.sh reescreve as referências no markdown para esses caminhos locais
    mkdir -p /tmp/issue/img
    while read -r secret file; do
      glab api "projects/$GL_PROJECT/uploads/$secret/$file" > "/tmp/issue/img/${secret:0:8}_$file" \
        || { rm -f "/tmp/issue/img/${secret:0:8}_$file"; issue_fail "falha ao baixar a imagem $file da issue #$ISSUE_ID"; }
    done < <(jq -r '(.description? // empty), (.[]? | objects | .body? // empty)
                    | scan("/uploads/([0-9a-f]{32})/([^)\\s]+)") | "\(.[0]) \(.[1])"' \
               /tmp/issue/issue.json /tmp/issue/comments.json | sort -u)
  fi
  if [[ "$GIT_SERVER_TYPE" == "onedev" ]]; then
    # anexos (/~downloads/projects/<id>/attachments/<uuid>/<arquivo>?v=<n>) da descrição e dos comentários -> /tmp/issue/img/<uuid8>_<arquivo>
    # o tod download exige a URL original do markdown (com ?v=) e infere o projeto pelo git do diretório atual
    # o issue-to-md.sh reescreve as referências no markdown para esses caminhos locais
    mkdir -p /tmp/issue/img
    while read -r url; do
      path="${url%%\?*}"; file="${path##*/}"; rest="${path%/*}"; uuid="${rest##*/}"
      tod download "$url" "/tmp/issue/img/${uuid:0:8}_$file" >/dev/null \
        || { rm -f "/tmp/issue/img/${uuid:0:8}_$file"; issue_fail "falha ao baixar o anexo $file da issue #$ISSUE_ID"; }
    done < <(jq -r '(.description? // empty), (.[]? | objects | .content? // empty)
                    | scan("/~downloads/projects/[0-9]+/attachments/[0-9a-f-]{36}/[^)\\s?]+(?:\\?v=[0-9]+)?")' \
               /tmp/issue/issue.json /tmp/issue/comments.json | sort -u)
  fi
  if [[ "$GIT_SERVER_TYPE" == "github" ]]; then
    # imagens anexas (user-attachments/assets/<uuid>) da descrição e dos comentários -> /tmp/issue/img/<uuid>.<ext>
    # em repo privado o link original dá 404: o body_html da API traz a URL assinada (private-user-images, jwt temporário)
    # o issue-to-md.sh reescreve as referências no markdown para esses caminhos locais
    mkdir -p /tmp/issue/img
    while read -r url; do
      uuid="$(grep -Eo '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' <<<"${url%%\?*}" | tail -n1)"
      ext="${url%%\?*}"; ext="${ext##*/}"; [[ "$ext" == *.* ]] && ext=".${ext##*.}" || ext=""
      curl -fsSL -o "/tmp/issue/img/$uuid$ext" "$url" \
        || { rm -f "/tmp/issue/img/$uuid$ext"; issue_fail "falha ao baixar a imagem $uuid da issue #$ISSUE_ID"; }
    done < <({ gh api -H "Accept: application/vnd.github.full+json" "repos/$REPO_PATH/issues/$ISSUE_ID" --jq '.body_html // empty'
               gh api --paginate -H "Accept: application/vnd.github.full+json" "repos/$REPO_PATH/issues/$ISSUE_ID/comments" --jq '.[].body_html // empty'
             } 2>/dev/null \
             | grep -Eo 'https://(private-user-images\.githubusercontent\.com|github\.com/user-attachments)/[^"]+' \
             | sed 's/&amp;/\&/g' | sort -u)
  fi
  issue-to-md.sh /tmp/issue \
    || issue_fail "falha ao converter a issue #$ISSUE_ID para markdown"
fi

# comenta na issue o stdout do agente (truncado) e o código de saída
post_issue_comment() { # $1=arquivo com o corpo do comentário
  case "$GIT_SERVER_TYPE" in
    onedev) tod issue add-comment "$ISSUE_ID" "$(cat "$1")" ;;
    gitlab) glab issue note "$ISSUE_ID" -R "$REPO_PATH" -m "$(cat "$1")" ;;
    github) gh issue comment "$ISSUE_ID" -R "$GH_HOST/$REPO_PATH" --body-file "$1" ;;
  esac
}

if [[ "${AUTONOMOUS_MODE:-false}" == "true" ]]; then
  # modo autônomo: roda o agente (sem exec) para capturar o stdout e comentar na issue
  AGENT_OUT=/tmp/agent-stdout.log
  AGENT_COMMENT=/tmp/agent-comment.md
  MAX_COMMENT_CHARS="${MAX_COMMENT_CHARS:-60000}"
  set +e
  "${@:-bash}" < /dev/null | tee "$AGENT_OUT"
  AGENT_RC=${PIPESTATUS[0]}
  set -e
  {
    echo "Execução do agente finalizada (código de saída: $AGENT_RC)."
    echo
    echo '```'
    tail -c "$MAX_COMMENT_CHARS" "$AGENT_OUT"
    echo
    echo '```'
  } > "$AGENT_COMMENT"
  post_issue_comment "$AGENT_COMMENT" \
    || echo "AVISO: falha ao comentar a saída do agente na issue #$ISSUE_ID" >&2
  exit "$AGENT_RC"
fi

exec "${@:-bash}"
