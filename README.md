# 🚀 Post Install Pop!\_OS (Script Automatizado)

Este repositório contém um **script de pós-formatação** (`pos-install.sh`) feito sob medida para **Pop!\_OS / Ubuntu / Debian**.  
Ele instala e configura **todas as ferramentas essenciais** de desenvolvimento, personalização do sistema e produtividade.

---

## 📋 O que o script faz?

### 🔑 Pré-requisitos

- Pede a senha **apenas uma vez** (mantém o `sudo` ativo durante toda a execução).
- Protege contra **erros de lock do APT** (causados por `packagekitd` ou atualizações automáticas).
- Continua mesmo se algum passo falhar, registrando tudo em um log (`~/postinstall-fail.log`).

---

### 🖥️ Shell e Terminal

- Instala o **ZSH** e define como shell padrão.
- Configura o **Starship Prompt** com preset nerd-font-symbols.
- Instala e configura **Zinit** com os plugins:
  - `zsh-users/zsh-autosuggestions`
  - `zdharma-continuum/fast-syntax-highlighting`
- Adiciona aliases úteis:
  - `cat` usando **bat** com tema Nord
  - `ls` usando **eza** com ícones e cores
  - atalhos para Docker, NPM, PNPM, NestJS e ShadCN

---

### 🔠 Fontes

- Instala via Nerd Fonts:
  - **Fira Code**
  - **Fira Mono**
  - **JetBrains Mono**

---

### 🌈 Personalização GNOME

- Instala **GNOME Tweaks** e **extensões**.
- Instala **temas do Kali Linux** (shell + ícones).
- Aplica o **tema Catppuccin Frappe** ao GNOME Terminal como padrão.

---

### 🐙 Git

- Instala e configura o **Git**:
  - Nome e email global
  - Branch padrão = `main`

---

### 🌐 Navegadores e IDEs

- Instala navegadores:
  - **Google Chrome**
  - **Brave Browser**
- Instala **Visual Studio Code**.

---

### 🧑‍💻 Node.js e Ecosistema

- Instala o **NVM**.
- Instala a **última versão do Node.js**.
- Define o Node como **default global** no NVM.
- Instala o **PNPM**.

---

### 🐍 Python e Data Science

- Instala e configura **pyenv**.
- Instala a **última versão estável do Python** via pyenv.
- Define o Python do pyenv como **default global**.
- Garante `pip`, `setuptools`, `wheel` atualizados.
- Instala a **última versão do Anaconda** via pyenv.
- Instala o **pipx**.
- Instala o **pipenv** via pipx.

---

### 📦 CLI Tools

- Instala:
  - **bat** (visualização de arquivos com sintaxe colorida)
  - **eza** (substituto moderno do `ls`)
  - **zoxide** (substituto inteligente do `cd`)

---

### 🐳 Containers e Virtualização

- Instala o **Docker Engine** e **plugins**:
  - docker-ce, docker-ce-cli, containerd.io
  - docker-buildx-plugin, docker-compose-plugin
- Adiciona o usuário ao grupo `docker`.
- Instala o **Docker Desktop (Linux)**.
- Instala o **Podman** via repositório oficial libcontainers.

---

### 📦 Flatpak (Apps de Produtividade)

Instala e habilita o **Flathub** e adiciona os seguintes apps:

- [OBS Studio](https://flathub.org/apps/com.obsproject.Studio)
- [DBeaver](https://flathub.org/apps/io.dbeaver.DBeaverCommunity)
- [JetBrains Rider](https://flathub.org/apps/com.jetbrains.Rider)
- [Postman](https://flathub.org/apps/com.getpostman.Postman)
- [Spotify](https://flathub.org/apps/com.spotify.Client)
- [Android Studio](https://flathub.org/apps/com.google.AndroidStudio)
- [Zen Browser](https://flathub.org/apps/app.zen_browser.zen)
- [VLC](https://flathub.org/apps/org.videolan.VLC)
- [Flameshot](https://flathub.org/apps/org.flameshot.Flameshot)
- [Steam](https://flathub.org/apps/com.valvesoftware.Steam)

---

### 🖱️ LogiOps (MX Master Config)

- Compila e instala o **LogiOps** (daemon de configuração para mouses Logitech).
- Aplica configurações personalizadas para o **MX Master 3**:
  - **Perfil default**: gestos ←/→ = `Ctrl+Alt+Left/Right`
  - **Perfil pop**: gestos ←/→ = `Ctrl+Super+Up/Down`
  - Botão de gesto → exibe **áreas de trabalho** (tecla Super).
- Pergunta no setup qual perfil aplicar.

---

## Observações

- LogiOps (MX Master da Logitech)
- Se você não usa MX Master, pode pular a instalação.
- Basta comentar a linha no final do script:

# run_step install_logiops_and_config

## Pular qualquer etapa

Qualquer função pode ser comentada em RUN ORDER. Exemplos:

# run_step install_flatpak_apps # não instalar os Flatpaks

# run_step install_browsers_editors # não instalar Chrome/Brave/VSCode

# run_step install_pyenv_and_latest_python # não configurar Python/pyenv

## ⚡ Como usar

1. Clone ou copie o script `pos-install.sh`.
2. Dê permissão de execução:
   ```bash
   chmod +x pos-install.sh
   ```
3. Abra o arquivo no seu editor de texto, e altere no inicio as configs do git, colocando seu nome e email para ele setar como global no sistema;
4. Execute usando ./post-install.sh
