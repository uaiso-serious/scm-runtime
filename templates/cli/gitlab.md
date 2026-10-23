# Exemplos de Comandos CLI (`glab`)

### Issues

```bash
# Ver detalhes de uma issue
glab issue view ${ISSUE_REF} -R "${REPO_PATH}"

# Comentar em uma issue
glab issue note ${ISSUE_REF} -R "${REPO_PATH}" -m "Seu comentário em Markdown"
```

### Merge Requests

```bash
# Abrir um Merge Request da branch atual para a branch base
glab mr create -R "${REPO_PATH}" \
  --title "Título do Merge Request" \
  --description "Descrição das alterações" \
  --source-branch "${GIT_BRANCH}" \
  --target-branch "${GIT_BASE_BRANCH}" \
  --yes

# Ver detalhes de um Merge Request
glab mr view <MR_ID> -R "${REPO_PATH}"

# Comentar em um Merge Request
glab mr note <MR_ID> -R "${REPO_PATH}" -m "Seu comentário em Markdown"
```
