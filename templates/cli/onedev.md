# Exemplos de Comandos CLI (`tod`)

### Issues

```bash
# Ver detalhes de uma issue
tod issue get ${ISSUE_REF}

# Listar comentários de uma issue
tod issue get-comments ${ISSUE_REF}

# Comentar em uma issue
tod issue add-comment ${ISSUE_REF} "Seu comentário em Markdown"
```

### Pull Requests

```bash
# Abrir um Pull Request da branch atual para a branch base
tod pr create "Título do Pull Request" \
  --description "Descrição das alterações" \
  --source-branch "${GIT_BRANCH}" \
  --target-branch "${GIT_BASE_BRANCH}"

# Ver detalhes de um Pull Request
tod pr get <PR_ID>

# Comentar em um Pull Request
tod pr add-comment <PR_ID> "Seu comentário em Markdown"
```
