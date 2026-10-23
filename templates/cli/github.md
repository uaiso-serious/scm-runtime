# Exemplos de Comandos CLI (`gh`)

### Issues

```bash
# Ver detalhes de uma issue
gh issue view ${ISSUE_REF} -R "${GH_HOST}/${REPO_PATH}"

# Comentar em uma issue
gh issue comment ${ISSUE_REF} -R "${GH_HOST}/${REPO_PATH}" --body "Seu comentário em Markdown"
```

### Pull Requests

```bash
# Abrir um Pull Request da branch atual para a branch base
gh pr create -R "${GH_HOST}/${REPO_PATH}" \
  --title "Título do Pull Request" \
  --body "Descrição das alterações" \
  --head "${GIT_BRANCH}" \
  --base "${GIT_BASE_BRANCH}"

# Ver detalhes de um Pull Request
gh pr view <PR_ID> -R "${GH_HOST}/${REPO_PATH}"

# Comentar em um Pull Request
gh pr comment <PR_ID> -R "${GH_HOST}/${REPO_PATH}" --body "Seu comentário em Markdown"
```
