#!/usr/bin/env bash
# postinstall-apps.sh v16 - Pop!_OS
# - Sudo 1x (keep-alive), resiliência com logs, proteção contra locks APT
# - Browsers, VS Code, Node (NVM/PNPM), Python (pyenv+pipenv+Anaconda), Docker Engine+Desktop, Podman
# - Nerd Fonts, Starship, Zinit+aliases, eza/bat/zoxide, Flatpaks (Zen/VLC/Flameshot/Steam)
# - LogiOps, GNOME Tweaks, Kali themes/icons, Catppuccin GNOME Terminal (Frappe default)

set -Euo pipefail

### ========= CONFIG =========
GIT_NAME="${GIT_NAME:-Jhon Doe}" # Coloque o seu nome aqui
GIT_EMAIL="${GIT_EMAIL:-seu-email@exemplo.com}" # Coloque o seu email aqui
LOGI_PROFILE="${LOGI_PROFILE:-}"  # default|pop (se vazio, pergunta)

### ========= HELPERS =========
log()  { echo -e "\033[1;32m[OK]\033[0m $*"; }
info() { echo -e "\033[1;34m[i]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }

has() { command -v "$1" >/dev/null 2>&1; }

ensure_apt_pkg() {
  local pkg="$1"
  dpkg -s "$pkg" >/dev/null 2>&1 || apt_safe install -y "$pkg"
}

append_once() {
  local line="$1" file="$2"
  mkdir -p "$(dirname "$file")"; touch "$file"
  grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

font_family_exists() {
  fc-list : family | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -iqE "$1"
}

# === APT Lock handling ===
stop_apt_lockers() {
  sudo systemctl stop packagekit apt-daily.service apt-daily.timer \
    apt-daily-upgrade.service apt-daily-upgrade.timer unattended-upgrades 2>/dev/null || true
  sudo killall -q packagekitd 2>/dev/null || true
}
wait_apt_locks() {
  local locks=(/var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/cache/apt/archives/lock)
  for _ in {1..120}; do
    if ! sudo fuser "${locks[@]}" >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  return 0
}
apt_safe() {
  stop_apt_lockers
  wait_apt_locks
  sudo DEBIAN_FRONTEND=noninteractive \
    apt-get -o Dpkg::Use-Pty=0 -o Dpkg::Lock::Timeout=600 "$@"
}
apt_update() {
  info "Atualizando pacotes..."
  apt_safe update -y && apt_safe upgrade -y
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

### ========= 1) ZSH =========
install_and_set_zsh() {
  ensure_apt_pkg zsh
  if [[ "${SHELL:-}" != "$(command -v zsh)" ]]; then
    chsh -s "$(command -v zsh)" "$USER" || warn "Não deu pra fixar zsh agora."
  fi
  touch "$HOME/.zshrc"
}

### ========= 2) Git =========
install_git_cfg() {
  ensure_apt_pkg git
  git config --global user.name "$GIT_NAME"
  git config --global user.email "$GIT_EMAIL"
  git config --global init.defaultBranch main
}

### ========= 3) NVM / Node / PNPM =========
install_nvm_node_pnpm() {
  if [[ ! -d "$HOME/.nvm" ]]; then
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  fi
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  nvm install node
  nvm alias default node
  curl -fsSL https://get.pnpm.io/install.sh | sh -
}

### ========= 4) Python (pyenv + último Python + pip + Anaconda + pipenv) =========
install_pyenv_and_latest_python() {
  info "Instalando pyenv + Python mais recente + pip (upgrade) + Anaconda + pipx/pipenv..."

  # deps de build do CPython
  apt_safe install -y make build-essential libssl-dev zlib1g-dev \
    libbz2-dev libreadline-dev libsqlite3-dev curl llvm libncursesw5-dev \
    xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev \
    ca-certificates git

  # pyenv (sem sudo)
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

  # última versão estável x.y.z
  local latest
  latest="$(pyenv install -l | sed 's/^[[:space:]]*//' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | tail -1)"
  if [[ -z "$latest" ]]; then
    warn "Não consegui detectar a última versão do Python via pyenv."
    return 1
  fi

  if ! pyenv versions --bare | grep -qx "$latest"; then
    pyenv install "$latest"
  fi

  # define como default do usuário
  pyenv global "$latest"
  hash -r

  # garante pip e amigos atualizados no Python global do pyenv
  python -m ensurepip --upgrade || true
  python -m pip install --upgrade pip setuptools wheel || true

  # instala Anaconda mais recente via pyenv (não muda o global)
  local latest_conda
  latest_conda="$(pyenv install -l | sed 's/^[[:space:]]*//' | grep -E '^anaconda3-[0-9]+' | tail -1 || true)"
  if [[ -n "${latest_conda:-}" ]]; then
    if ! pyenv versions --bare | grep -qx "$latest_conda"; then
      info "Instalando $latest_conda via pyenv (isso pode demorar)..."
      pyenv install "$latest_conda"
    fi
    # valida pip dentro do anaconda (opcional)
    PYENV_VERSION="$latest_conda" python -m pip --version >/dev/null 2>&1 || true
  else
    warn "Não encontrei uma versão de anaconda3 na lista do pyenv (seguindo sem Anaconda)."
  fi

  # pipx + pipenv (usando Python do pyenv)
  if ! has pipx; then
    apt_safe install -y pipx || true
    if ! has pipx; then
      python -m ensurepip --upgrade || true
      python -m pip install --user pipx
      export PATH="$HOME/.local/bin:$PATH"
    fi
  fi
  pipx ensurepath || true
  pipx install --python "$(pyenv which python)" pipenv || pipx reinstall pipenv || true
  if ! has pipenv; then
    python -m pip install --user pipenv || true
  fi

  log "pyenv ativo com Python $latest (global), Anaconda (se disponível) instalada e pipenv pronto"
}

### ========= 5) Nerd Fonts =========
install_fonts_wget() {
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

### ========= 6) Starship =========
install_starship_and_preset() {
  curl -sS https://starship.rs/install.sh | sh -s -- -y
  mkdir -p "$HOME/.config"
  starship preset nerd-font-symbols -o "$HOME/.config/starship.toml" || true
}

### ========= 7) Flatpak Apps =========
install_flatpak_apps() {
  ensure_apt_pkg flatpak
  ensure_apt_pkg gnome-software-plugin-flatpak
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

### ========= 8) Browsers + VS Code =========
install_browsers_editors() {
  # Chrome
  if ! has google-chrome; then
    wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    apt_safe install -y ./google-chrome-stable_current_amd64.deb || true
    rm -f google-chrome-stable_current_amd64.deb
  fi
  # Brave
  if ! has brave-browser; then
    ensure_apt_pkg curl
    sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg arch=amd64] https://brave-browser-apt-release.s3.brave.com/ stable main" \
      | sudo tee /etc/apt/sources.list.d/brave-browser-release.list >/dev/null
    apt_safe update -y
    apt_safe install -y brave-browser
  fi
  # VS Code
  if ! has code; then
    ensure_apt_pkg wget; ensure_apt_pkg gpg
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
    sudo install -o root -g root -m 644 microsoft.gpg /etc/apt/trusted.gpg.d/
    echo "deb [arch=amd64] https://packages.microsoft.com/repos/code stable main" \
      | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
    apt_safe update -y
    apt_safe install -y code
    rm -f microsoft.gpg
  fi
}

### ========= 9) Docker Engine + Podman + Docker Desktop =========
install_docker_podman_desktop() {
  apt_safe update -y
  apt_safe install -y ca-certificates curl gnupg
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

  apt_safe update -y
  apt_safe install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker "$USER" || true

  run_step install_podman

  apt_safe install -y uidmap dbus-user-session fuse-overlayfs
  local tmp_deb; tmp_deb="$(mktemp --suffix=.deb)"
  wget -q https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb -O "$tmp_deb"
  apt_safe install -y "$tmp_deb" || sudo dpkg -i "$tmp_deb" || true
  rm -f "$tmp_deb"
}
install_podman() {
  info "Instalando Podman (repo oficial libcontainers)..."
  apt_safe install -y software-properties-common curl
  . /etc/os-release
  sudo sh -c "echo 'deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_${VERSION_ID}/ /' > /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list"
  curl -fsSL "https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_${VERSION_ID}/Release.key" | \
    sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/libcontainers.gpg
  apt_safe update -y
  apt_safe install -y podman
}

### ========= 10) CLI Tools =========
install_cli_tools() {
  apt_safe install -y bat gpg
  sudo mkdir -p /etc/apt/keyrings
  if [ ! -f /etc/apt/keyrings/gierens.gpg ]; then
    wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | \
      sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
  fi
  echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | \
    sudo tee /etc/apt/sources.list.d/gierens.list >/dev/null
  sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
  apt_safe update -y
  apt_safe install -y eza zoxide
}

### ========= 11) Zinit + Aliases =========
configure_zinit_and_aliases() {
  ensure_apt_pkg git
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

  # pyenv env (reforço)
  append_once 'export PYENV_ROOT="$HOME/.pyenv"' "$ZSHRC"
  append_once 'export PATH="$PYENV_ROOT/bin:$PATH"' "$ZSHRC"
  append_once 'eval "$(pyenv init -)"' "$ZSHRC"

  # Starship
  append_once 'eval "$(starship init zsh)"' "$ZSHRC"

  # Aliases
  append_once 'alias bat="batcat"' "$ZSHRC"
  append_once 'alias cat="bat --theme=Nord"' "$ZSHRC"
  append_once 'alias l="ls -la"' "$ZSHRC"
  append_once 'alias ls="eza --color=always --long --git --icons=always --no-filesize --no-time --no-user --no-permissions"' "$ZSHRC"
  # append_once 'alias cd="z"' "$ZSHRC"
  append_once 'alias docker-compose="docker compose"' "$ZSHRC"
  append_once 'alias dcu="docker compose up -d"' "$ZSHRC"
  append_once 'alias ndev="npm run dev"' "$ZSHRC"
  append_once 'alias pdev="pnpm run dev"' "$ZSHRC"
  append_once 'alias chadi="npx shadcn@latest add"' "$ZSHRC"
  append_once 'alias pchadi="pnpm dlx shadcn@latest add"' "$ZSHRC"
  append_once 'alias nestd="npm run start:dev"' "$ZSHRC"
  append_once 'alias dlx="pnpm dlx"' "$ZSHRC"
}

### ========= 12) LogiOps =========
install_logiops_and_config() {
  apt_safe install -y build-essential cmake libevdev-dev libudev-dev libconfig++-dev git
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
  sudo systemctl enable logid >/dev/null 2>&1 || true
  sudo systemctl restart logid || true
}

### ========= 13) GNOME Tweaks + Themes =========
install_gnome_tweaks_and_themes() {
  apt_safe install -y gnome-tweaks gnome-shell-extensions
  apt_safe install -y kali-themes kali-icon-theme || true
}

### ========= 14) Catppuccin GNOME Terminal (installer oficial + default Frappe) =========
install_catppuccin_frappe_terminal() {
  info "Instalando Catppuccin GNOME Terminal (installer oficial) e definindo 'Frappe' como padrão..."
  ensure_apt_pkg python3
  ensure_apt_pkg curl
  ensure_apt_pkg dconf-cli

  # installer oficial (v1.0.0)
  set +e
  curl -fsSL https://raw.githubusercontent.com/catppuccin/gnome-terminal/v1.0.0/install.py | python3 -
  local rc=$?
  set -e
  if [ $rc -ne 0 ]; then
    warn "Installer do Catppuccin retornou rc=$rc; tentando setar perfil se existir."
  fi

  # procurar o perfil "Catppuccin Frappe" e definir como default
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
run_step apt_update
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
run_step install_gnome_tweaks_and_themes
run_step install_catppuccin_frappe_terminal

echo
if [[ ${#FAILED_STEPS[@]} -gt 0 ]]; then
  warn "Algumas etapas falharam:"
  for step in "${FAILED_STEPS[@]}"; do echo "  - $step"; done
  echo "Veja detalhes em: $LOGFILE"
else
  log "🎉 Todas as etapas foram concluídas sem erros!"
fi
