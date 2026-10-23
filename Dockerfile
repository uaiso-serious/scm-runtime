FROM ubuntu:26.04

ARG USERNAME=agent
ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=America/Sao_Paulo

# TODO juntar os RUN apt-get em um só (com limpeza de /var/lib/apt/lists) ao sair do desenvolvimento;
# separados por ora para aproveitar o cache de camadas do Docker
RUN apt-get update

RUN apt-get install -y --no-install-recommends \
    git curl ca-certificates wget jq

RUN if id ubuntu >/dev/null 2>&1; then userdel -r ubuntu; fi \
 && groupadd --gid ${USER_GID} ${USERNAME} \
 && useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/bash ${USERNAME}

COPY entrypoint.sh issue-to-md.sh /usr/local/bin/
COPY templates/ /usr/local/share/scm-runtime/templates/

RUN chmod 755 /usr/local/bin/entrypoint.sh /usr/local/bin/issue-to-md.sh \
 && mkdir /workspace && chown ${USERNAME}:${USERNAME} /workspace

USER ${USERNAME}
WORKDIR /workspace

ENV PATH="/home/${USERNAME}/.local/share/mise/shims:/home/${USERNAME}/.local/bin:${PATH}" \
    MISE_TRUSTED_CONFIG_PATHS="/workspace:/home/${USERNAME}/.config/mise"

RUN curl -fsSL https://mise.run | sh \
 && echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc

COPY --chown=${USERNAME}:${USERNAME} mise.toml /home/${USERNAME}/.config/mise/conf.d/10-scm.toml
RUN mise trust /home/${USERNAME}/.config/mise/conf.d/10-scm.toml \
 && mise trust /workspace \
 && mise install

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
