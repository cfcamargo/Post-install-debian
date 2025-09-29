#!/usr/bin/env bash
# postinstall-apps-fedora.sh v16 (Fedora Workstation)
# - Sudo 1x (keep-alive), resiliência com logs
# - Browsers, VS Code, Node (NVM/PNPM), Python (pyenv+pipenv+Anaconda), Docker Engine+Desktop, Podman
# - Nerd Fonts, Starship, Zinit+aliases, eza/bat/zoxide, Flatpaks (Zen/VLC/Flameshot/Steam)
# - LogiOps, GNOME Tweaks, Catppuccin GNOME Terminal (Frappe default)

set -Euo pipefail

### ========= CONFIG =========
GIT_NAME="${GIT_NAME:-Jhon Doe}"                 # Coloque o seu nome aqui
GIT_EMAIL="${GIT_EMAIL:-seu-email@exemplo.com}"  # Coloque o seu email aqui
LOGI_PROFILE="${LOGI_PROFILE:-}"                 # default|pop (se vazio, pergunta)

### ========= HELPERS =========
log()  { echo -e "\033[1;32m[OK]\033[0m $*"; }
info() { echo -e "\033[1;34m[i]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }
has()  { command -v "$1" >/dev/null 2>&1; }

append_once() {
  local line="$1" file="$2"
  mkdir -p "$(dirname "$file")"; touch "$file"
  grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

font_family_exists() {
  fc-list : family | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -iqE "$1"
}

### ========= DNF safe wrapper (com retries leves) =========
dnf_safe() {
  local tries=3
  local delay=5
  for i in $(seq 1 $tries); do
    if sudo dnf -y --setopt=install_weak_deps=False --best "$@"; then
      return 0
    fi
    warn "dnf falhou (tentativa $i/$tries). Tentando novamente em ${delay}s..."
    sleep "$delay"
  done
  return 1
}

ensure_pkg() {
  local pkg="$1"
  if ! rpm -q "$pkg" >/dev/null 2>&1; then
    dnf_safe install "$pkg"
  fi
}

### ========= SUDO keep-alive =========
ensure_sudo_keepalive() {
  if [[ $EUID -eq 0 ]]; then return 0; fi
  sudo -v || { echo "[x] preciso de sudo"; return 1; }
  while true; do
    sudo -n true 2>/dev/null || exit
    sleep 45
    kill -0 "$$" 2>/dev/null || exit
  done & disown
  return 0
}

### ========= Error handling wrapper =========
FAILED_STEPS=()
LOGFILE="$HOME/postinstall-fail.log"
: > "$LOGFILE"

run_step() {
  local fn="$1"
  info ">>> Executando $fn..."
  set +e
  $fn
  local rc=$?
  set -e
  if [ $rc -eq 0 ]; then
    log "$fn concluído"
  else
    warn "$fn FALHOU (veja $LOGFILE)"
    echo "[$(date +%F\ %T)] $fn falhou (rc=$rc)" >> "$LOGFILE"
    FAILED_STEPS+=("$fn")
  fi
}

### ========= 1) Atualização base =========
dnf_base_update() {
  info "Atualizando pacotes..."
  dnf_safe upgrade --refresh
}

### ========= 2) ZSH =========
install_and_set_zsh() {
  ensure_pkg zsh
  if [[ "${SHELL:-}" != "$(command -v zsh)" ]]; then
    chsh -s "$(command -v zsh)" "$USER" || warn "Não deu pra fixar zsh agora."
  fi
  touch "$HOME/.zshrc"
}

### ========= 3) Git =========
install_git_cfg() {
  ensure_pkg git
  git config --global user.name "$GIT_NAME"
  git config --global user.email "$GIT_EMAIL"
  git config --global init.defaultBranch main
}

### ========= 4) NVM / Node / PNPM =========
install_nvm_node_pnpm() {
  ensure_pkg curl
  if [[ ! -d "$HOME/.nvm" ]]; then
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  fi
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  nvm install node
  nvm alias default node
  curl -fsSL https://get.pnpm.io/install.sh | sh -
}

### ========= 5) Python (pyenv + último Python + pip + Anaconda + pipenv) =========
install_pyenv_and_latest_python() {
  info "Instalando pyenv + toolchain + Python + pipenv..."

  # Toolchain e deps de build do CPython em Fedora
  dnf_safe groupinstall "Development Tools"
  dnf_safe install \
    openssl-devel bzip2-devel readline-devel sqlite-devel zlib-devel \
    libffi-devel xz-devel tk-devel gdbm-devel ncurses-devel libuuid-devel \
    make curl ca-certificates patch git

  # pyenv (user)
  if [[ ! -d "$HOME/.pyenv" ]]; then
    git clone https://github.com/pyenv/pyenv.git ~/.pyenv
  fi

  # init no Zsh
  local ZSHRC="$HOME/.zshrc"
  append_once 'export PYENV_ROOT="$HOME/.pyenv"' "$ZSHRC"
  append_once 'export PATH="$PYENV_ROOT/bin:$PATH"' "$ZSHRC"
  append_once 'eval "$(pyenv init -)"' "$ZSHRC"

  # carregar pyenv nesta execução
  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)"

  # última versão estável
  local latest
  latest="$(pyenv install -l | sed 's/^[[:space:]]*//' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | tail -1)"
  if [[ -z "$latest" ]]; then
    warn "Não consegui detectar a última versão do Python via pyenv."
    return 1
  fi
  if ! pyenv versions --bare | grep -qx "$latest"; then
    pyenv install "$latest"
  fi
  pyenv global "$latest"
  hash -r

  python -m ensurepip --upgrade || true
  python -m pip install --upgrade pip setuptools wheel || true

  # Anaconda via pyenv (opcional)
  local latest_conda
  latest_conda="$(pyenv install -l | sed 's/^[[:space:]]*//' | grep -E '^anaconda3-[0-9]+' | tail -1 || true)"
  if [[ -n "${latest_conda:-}" ]]; then
    if ! pyenv versions --bare | grep -qx "$latest_conda"; then
      info "Instalando $latest_conda via pyenv (pode demorar)..."
      pyenv install "$latest_conda"
    fi
    PYENV_VERSION="$latest_conda" python -m pip --version >/dev/null 2>&1 || true
  else
    warn "Não encontrei uma versão de anaconda3 na lista do pyenv (seguindo sem Anaconda)."
  fi

  # pipx + pipenv
  dnf_safe install pipx || true
  export PATH="$HOME/.local/bin:$PATH"
  pipx ensurepath || true
  pipx install --python "$(pyenv which python)" pipenv || pipx reinstall pipenv || true
  has pipenv || python -m pip install --user pipenv || true

  log "pyenv ativo com Python $latest (global); Anaconda (se disponível) instalada; pipenv pronto."
}

### ========= 6) Nerd Fonts =========
install_fonts_wget() {
  dnf_safe install wget unzip fontconfig || true
  local FONTS_DIR="$HOME/.local/share/fonts"
  mkdir -p "$FONTS_DIR"
  for font in FiraCode FiraMono JetBrainsMono; do
    if ! font_family_exists "$font Nerd Font"; then
      local url="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/${font}.zip"
      local tmp_zip; tmp_zip="$(mktemp --suffix=.zip)"
      wget -q "$url" -O "$tmp_zip"
      unzip -o "$tmp_zip" -d "$FONTS_DIR" >/dev/null
      rm -f "$tmp_zip"
    fi
  done
  fc-cache -fv >/dev/null
}

### ========= 7) Starship =========
install_starship_and_preset() {
  curl -sS https://starship.rs/install.sh | sh -s -- -y
  mkdir -p "$HOME/.config"
  starship preset nerd-font-symbols -o "$HOME/.config/starship.toml" || true
}

### ========= 8) Flatpak Apps =========
install_flatpak_apps() {
  ensure_pkg flatpak
  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  flatpak install -y flathub \
    com.obsproject.Studio \
    io.dbeaver.DBeaverCommunity \
    com.jetbrains.Rider \
    com.getpostman.Postman \
    com.spotify.Client \
    com.google.AndroidStudio \
    app.zen_browser.zen \
    org.videolan.VLC \
    org.flameshot.Flameshot \
    com.valvesoftware.Steam
}

### ========= 9) Browsers + VS Code =========
install_browsers_editors() {
  ensure_pkg dnf-plugins-core
  ensure_pkg gpgme
  ensure_pkg curl
  ensure_pkg gnupg2 || true

  # Google Chrome (repo oficial)
  if ! has google-chrome; then
    sudo tee /etc/yum.repos.d/google-chrome.repo >/dev/null <<'REPO'
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/$basearch
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
REPO
    dnf_safe makecache
    dnf_safe install google-chrome-stable || true
  fi

  # Brave
  if ! has brave-browser; then
    sudo dnf config-manager --add-repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo || true
    sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc || true
    dnf_safe install brave-browser || true
  fi

  # VS Code
  if ! has code; then
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    sudo tee /etc/yum.repos.d/vscode.repo >/dev/null <<'REPO'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
REPO
    dnf_safe makecache
    dnf_safe install code
  fi
}

### ========= 10) Docker Engine + Podman + Docker Desktop =========
install_docker_podman_desktop() {
  ensure_pkg dnf-plugins-core
  sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo || true

  dnf_safe install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo systemctl enable --now docker || true
  sudo usermod -aG docker "$USER" || true

  run_step install_podman

  # Docker Desktop (RPM oficial)
  local tmp_rpm; tmp_rpm="$(mktemp --suffix=.rpm)"
  curl -fsSL https://desktop.docker.com/linux/main/amd64/docker-desktop-latest.x86_64.rpm -o "$tmp_rpm"
  # Dependências comuns para Desktop:
  dnf_safe install libXtst.x86_64 libXxf86vm.x86_64 fuse-overlayfs podman-docker jq slirp4netns || true
  sudo dnf -y install "$tmp_rpm" || sudo rpm -Uvh --force "$tmp_rpm" || true
  rm -f "$tmp_rpm"
}

install_podman() {
  info "Instalando Podman..."
  dnf_safe install podman uidmap dbus-user-session fuse-overlayfs
}

### ========= 11) CLI Tools =========
install_cli_tools() {
  dnf_safe install bat eza zoxide gpg which
  # em Fedora o binário é "bat" (não "batcat")
}

### ========= 12) Zinit + Aliases =========
configure_zinit_and_aliases() {
  ensure_pkg git
  local ZSHRC="$HOME/.zshrc"
  touch "$ZSHRC"

  # Zinit
  append_once 'export ZINIT_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"' "$ZSHRC"
  if ! grep -q 'source "$ZINIT_HOME/zinit.zsh"' "$ZSHRC"; then
    mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/zinit"
    git clone https://github.com/zdharma-continuum/zinit.git "${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"
    echo 'source "$ZINIT_HOME/zinit.zsh"' >> "$ZSHRC"
  fi
  append_once 'zinit light zsh-users/zsh-autosuggestions' "$ZSHRC"
  append_once 'zinit light zdharma-continuum/fast-syntax-highlighting' "$ZSHRC"

  # Node/PNPM env
  append_once 'export NVM_DIR="$HOME/.nvm"' "$ZSHRC"
  append_once '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"' "$ZSHRC"
  append_once 'export PNPM_HOME="$HOME/.local/share/pnpm"; case ":$PATH:" in *":$PNPM_HOME:"*) ;; *) export PATH="$PNPM_HOME:$PATH";; esac' "$ZSHRC"
  append_once 'export PATH="$HOME/.local/bin:$HOME/bin:$PATH"' "$ZSHRC"

  # pyenv env
  append_once 'export PYENV_ROOT="$HOME/.pyenv"' "$ZSHRC"
  append_once 'export PATH="$PYENV_ROOT/bin:$PATH"' "$ZSHRC"
  append_once 'eval "$(pyenv init -)"' "$ZSHRC"

  # Starship
  append_once 'eval "$(starship init zsh)"' "$ZSHRC"

  # Aliases (ajustados para Fedora)
  append_once 'alias bat="bat"' "$ZSHRC"
  append_once 'alias cat="bat --theme=Nord"' "$ZSHRC"
  append_once 'alias l="ls -la"' "$ZSHRC"
  append_once 'alias ls="eza --color=always --long --git --icons=always --no-filesize --no-time --no-user --no-permissions"' "$ZSHRC"
  append_once 'alias docker-compose="docker compose"' "$ZSHRC"
  append_once 'alias dcu="docker compose up -d"' "$ZSHRC"
  append_once 'alias ndev="npm run dev"' "$ZSHRC"
  append_once 'alias pdev="pnpm run dev"' "$ZSHRC"
  append_once 'alias chadi="npx shadcn@latest add"' "$ZSHRC"
  append_once 'alias pchadi="pnpm dlx shadcn@latest add"' "$ZSHRC"
  append_once 'alias nestd="npm run start:dev"' "$ZSHRC"
  append_once 'alias dlx="pnpm dlx"' "$ZSHRC"
}

### ========= 13) LogiOps =========
install_logiops_and_config() {
  # Deps em Fedora
  dnf_safe install cmake gcc-c++ libevdev-devel systemd-devel libconfig-devel git

  if ! has logid; then
    local tmpdir; tmpdir="$(mktemp -d)"
    git clone --depth=1 https://github.com/PixlOne/logiops.git "$tmpdir/logiops"
    cmake -S "$tmpdir/logiops" -B "$tmpdir/logiops/build"
    cmake --build "$tmpdir/logiops/build"
    sudo cmake --install "$tmpdir/logiops/build"
    rm -rf "$tmpdir"
  fi

  local PROFILE="$LOGI_PROFILE"
  if [[ -z "$PROFILE" ]]; then
    echo
    echo "Qual perfil do LogiOps deseja usar?"
    echo "  1) default  (gestos ←/→ = Ctrl+Alt+Left/Right)"
    echo "  2) pop      (gestos ←/→ = Ctrl+Super+Up/Down)"
    read -rp "Escolha [1/2] (padrão: 1): " opt
    case "${opt:-1}" in
      2) PROFILE="pop" ;;
      *) PROFILE="default" ;;
    esac
  fi

  local CFG_CONTENT
  if [[ "$PROFILE" == "pop" ]]; then
    CFG_CONTENT=$(cat <<'CFG'
devices: ({
  name: "Wireless Mouse MX Master 3";

  smartshift: { on: true; threshold: 30; torque: 50; }
  hiresscroll: { hires: true; invert: false; target: false; }
  dpi: 1000;

  buttons: (
    {
      cid: 0xC3;
      action = {
        type: "Gestures";
        gestures: (
          { direction: "Left";  mode: "OnRelease"; action = { type: "Keypress"; keys: ["KEY_LEFTCTRL","KEY_LEFTMETA","KEY_UP"];   }; },
          { direction: "Right"; mode: "OnRelease"; action = { type: "Keypress"; keys: ["KEY_LEFTCTRL","KEY_LEFTMETA","KEY_DOWN"]; }; },
          { direction: "None";  mode: "OnRelease"; action = { type: "Keypress"; keys: ["KEY_LEFTMETA"]; }; }
        );
      };
    }
  );
});
CFG
)
  else
    CFG_CONTENT=$(cat <<'CFG'
devices: ({
  name: "Wireless Mouse MX Master 3";

  smartshift: { on: true; threshold: 30; torque: 50; }
  hiresscroll: { hires: true; invert: false; target: false; }
  dpi: 1000;

  buttons: (
    {
      cid: 0xC3;
      action = {
        type: "Gestures";
        gestures: (
          { direction: "Left";  mode: "OnRelease"; action = { type: "Keypress"; keys: ["KEY_LEFTCTRL","KEY_LEFTALT","KEY_LEFT"];  }; },
          { direction: "Right"; mode: "OnRelease"; action = { type: "Keypress"; keys: ["KEY_LEFTCTRL","KEY_LEFTALT","KEY_RIGHT"]; }; },
          { direction: "None";  mode: "OnRelease"; action = { type: "Keypress"; keys: ["KEY_LEFTMETA"]; }; }
        );
      };
    }
  );
});
CFG
)
  fi
  echo "$CFG_CONTENT" | sudo tee /etc/logid.cfg >/dev/null
  sudo systemctl enable --now logid || true
}

### ========= 14) GNOME Tweaks =========
install_gnome_tweaks() {
  dnf_safe install gnome-tweaks gnome-extensions-app dconf dconf-editor || true
  # Observação: temas/ícones "Kali" não têm pacote oficial no Fedora.
  # Se quiser, depois instalamos um tema GTK (Orchis, WhiteSur, etc.) — posso te passar um passo-a-passo.
}

### ========= 15) Catppuccin GNOME Terminal (installer oficial + default Frappe) =========
install_catppuccin_frappe_terminal() {
  info "Instalando Catppuccin GNOME Terminal (installer oficial) e definindo 'Frappe' como padrão..."
  ensure_pkg python3
  ensure_pkg curl
  ensure_pkg dconf
  ensure_pkg glib2

  set +e
  curl -fsSL https://raw.githubusercontent.com/catppuccin/gnome-terminal/v1.0.0/install.py | python3 -
  local rc=$?
  set -e
  if [ $rc -ne 0 ]; then
    warn "Installer do Catppuccin retornou rc=$rc; tentando setar perfil se existir."
  fi

  local base="/org/gnome/terminal/legacy/profiles:"
  local ids; ids="$(dconf list ${base}/ 2>/dev/null | tr -d '/')" || true
  local found_id=""
  for id in $ids; do
    local vname; vname="$(dconf read ${base}/:$id/visible-name 2>/dev/null || echo '')"
    if echo "$vname" | grep -q "Catppuccin Frappe"; then
      found_id="$id"; break
    fi
  done
  if [[ -n "$found_id" ]]; then
    gsettings set org.gnome.Terminal.ProfilesList default "$found_id" || true
    gsettings set org.gnome.terminal.legacy.profiles:/org/gnome/terminal/legacy/profiles:/:$found_id/ use-theme-colors false || true
    log "Perfil 'Catppuccin Frappe' definido como padrão ($found_id)"
  else
    warn "Não encontrei o perfil 'Catppuccin Frappe'. Abra o GNOME Terminal e verifique os perfis."
  fi
}

### ========= RUN ORDER =========
run_step ensure_sudo_keepalive
run_step dnf_base_update
run_step install_and_set_zsh
run_step install_git_cfg
run_step install_nvm_node_pnpm
run_step install_pyenv_and_latest_python
run_step install_fonts_wget
run_step install_starship_and_preset
run_step install_flatpak_apps
run_step install_browsers_editors
run_step install_docker_podman_desktop
run_step install_cli_tools
run_step configure_zinit_and_aliases
run_step install_logiops_and_config
run_step install_gnome_tweaks
run_step install_catppuccin_frappe_terminal

echo
if [[ ${#FAILED_STEPS[@]} -gt 0 ]]; then
  warn "Algumas etapas falharam:"
  for step in "${FAILED_STEPS[@]}"; do echo "  - $step"; done
  echo "Veja detalhes em: $LOGFILE"
else
  log "🎉 Todas as etapas foram concluídas sem erros!"
fi
