# Standalone (zsh/fish) demo base: reuses bash demo-base (evp, fonts, mock
# claude) and adds flyline-standalone + shell widgets.

FROM demo-base

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    zsh \
    fish \
    && rm -rf /var/lib/apt/lists/*

# flyline-zsh-integration-artifact: lib + standalone
COPY --from=standalone-artifact /flyline-standalone /home/john/bin/flyline-standalone
COPY scripts/flyline.zsh /home/john/lib/scripts/flyline.zsh
COPY scripts/flyline.fish /home/john/lib/scripts/flyline.fish

RUN chmod +x /home/john/bin/flyline-standalone \
    && chown -R john:john /home/john/bin/flyline-standalone /home/john/lib

USER john

ENV FLYLINE_BIN=/home/john/bin/flyline-standalone
ENV PATH="/home/john/bin:${PATH}"

# zsh: enable flyline widget; keep a simple prompt for readable demos.
RUN printf '%s\n' \
    'export FLYLINE_BIN=/home/john/bin/flyline-standalone' \
    'export PATH="/home/john/bin:$PATH"' \
    'PROMPT="%n@%m %1~ %# "' \
    'RPROMPT=""' \
    '[[ -r /home/john/lib/scripts/flyline.zsh ]] && . /home/john/lib/scripts/flyline.zsh' \
    > /home/john/.zshrc

# fish: conf.d auto-load (mirrors install.sh); simple prompt.
RUN mkdir -p /home/john/.config/fish/conf.d /home/john/.config/fish/functions \
    && printf '%s\n' \
    'set -gx FLYLINE_BIN /home/john/bin/flyline-standalone' \
    'set -gx PATH /home/john/bin $PATH' \
    'test -r /home/john/lib/scripts/flyline.fish; and source /home/john/lib/scripts/flyline.fish' \
    > /home/john/.config/fish/conf.d/flyline.fish \
    && printf '%s\n' \
    'function fish_prompt' \
    '    printf "%s@%s %s> " $USER (prompt_hostname) (prompt_pwd)' \
    'end' \
    > /home/john/.config/fish/functions/fish_prompt.fish
