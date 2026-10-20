#!/usr/bin/env bash
# Installs everything Atlas needs to run without Docker:
#   asdf -> Erlang + Elixir (versions from .tool-versions) -> mix setup.
#
# Supports macOS (Homebrew) and Debian/Ubuntu (apt). Erlang is compiled from
# source the first time, which takes 5-15 minutes.
set -euo pipefail

cd "$(dirname "$0")/.."

say() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\n\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

OS="$(uname -s)"
ASDF_LEGACY_VERSION="v0.15.0"

install_build_deps() {
  case "$OS" in
    Darwin)
      have brew || die "Homebrew is required on macOS: https://brew.sh"
      say "Installing Erlang build dependencies with Homebrew"
      brew install autoconf openssl@3 >/dev/null
      ;;
    Linux)
      if have apt-get; then
        say "Installing Erlang build dependencies with apt (needs sudo)"
        local SUDO=""
        [ "$(id -u)" -ne 0 ] && SUDO="sudo"
        $SUDO apt-get update -y
        $SUDO apt-get install -y build-essential autoconf m4 libncurses-dev libssl-dev \
          unzip curl git ca-certificates
      else
        say "Not a Debian/Ubuntu system: make sure a C compiler, autoconf, m4, ncurses and OpenSSL headers are installed."
      fi
      ;;
    *) die "Unsupported OS: $OS. Use Docker instead: make up" ;;
  esac
}

install_asdf() {
  if have asdf; then
    say "asdf found: $(asdf --version 2>/dev/null | head -1)"
    return
  fi

  if have brew; then
    say "Installing asdf with Homebrew"
    brew install asdf
  else
    say "Installing asdf ($ASDF_LEGACY_VERSION) into ~/.asdf"
    git clone https://github.com/asdf-vm/asdf.git "$HOME/.asdf" --branch "$ASDF_LEGACY_VERSION" --depth 1
    # shellcheck disable=SC1091
    . "$HOME/.asdf/asdf.sh"
    add_to_shell_rc '. "$HOME/.asdf/asdf.sh"'
  fi
}

add_to_shell_rc() {
  local line="$1"
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$rc" ] && ! grep -qF "$line" "$rc"; then
      printf '\n# Added by Atlas installer\n%s\n' "$line" >> "$rc"
    fi
  done
}

install_runtimes() {
  export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"

  for plugin in erlang elixir; do
    if ! asdf plugin list 2>/dev/null | grep -qx "$plugin"; then
      say "Adding asdf plugin: $plugin"
      asdf plugin add "$plugin"
    fi
  done

  # Lean Erlang build: no Java, no wxWidgets GUI, no ODBC.
  export KERL_CONFIGURE_OPTIONS="--without-javac --without-wx --without-odbc --without-jinterface"
  if [ "$OS" = "Darwin" ]; then
    KERL_CONFIGURE_OPTIONS="$KERL_CONFIGURE_OPTIONS --with-ssl=$(brew --prefix openssl@3)"
  fi
  export KERL_BUILD_DOCS=no

  say "Installing $(tr '\n' ' ' < .tool-versions)(Erlang compiles from source the first time)"
  asdf install

  add_to_shell_rc 'export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"'
}

setup_app() {
  say "Installing Hex and Rebar"
  mix local.hex --force --if-missing >/dev/null
  mix local.rebar --force --if-missing >/dev/null

  say "Fetching dependencies, creating the database, building assets"
  mix setup
}

main() {
  if have elixir && have erl && [ "${FORCE_ASDF:-}" != "1" ] && elixir_matches; then
    say "Elixir $(elixir_version) and Erlang/OTP $(otp_version) already match .tool-versions"
  else
    install_build_deps
    install_asdf
    install_runtimes
  fi

  setup_app

  say "Done. Start Atlas with:  make server   then open http://localhost:4000"
  if ! have claude && ! have codex && ! have cursor-agent && ! have gemini; then
    say "No AI CLI found. Install one (make clis) or pick the 'mock' backend to try Atlas offline."
  fi
}

elixir_version() { elixir -e 'IO.write(System.version())' 2>/dev/null; }
otp_version() { erl -noshell -eval 'io:put_chars(erlang:system_info(otp_release)), halt().' 2>/dev/null; }

elixir_matches() {
  local want_elixir want_otp
  want_elixir="$(awk '/^elixir/ {print $2}' .tool-versions | cut -d- -f1)"
  want_otp="$(awk '/^erlang/ {print $2}' .tool-versions | cut -d. -f1)"
  [ "$(elixir_version)" = "$want_elixir" ] && [ "$(otp_version)" = "$want_otp" ]
}

main "$@"
