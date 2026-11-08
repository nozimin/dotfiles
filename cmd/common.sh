# cmd/setup と cmd/install_brew から source する共通関数
# shellcheck shell=bash

# shellcheck disable=SC2034 # source 先で使う
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC2034
LIB_DIR="$REPO_ROOT/lib"
# shellcheck disable=SC2034
MARKER="config_for_mac"

if [ -t 1 ]; then
  C_BLUE=$'\033[1;34m' C_GREEN=$'\033[1;32m' C_YELLOW=$'\033[1;33m' C_RED=$'\033[1;31m' C_RESET=$'\033[0m'
else
  C_BLUE='' C_GREEN='' C_YELLOW='' C_RED='' C_RESET=''
fi

step()  { printf '\n%s==> %s%s\n' "$C_BLUE" "$*" "$C_RESET"; }
ok()    { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()  { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
error() { printf '%s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }

# 表示用に $HOME を ~ に置き換える
pretty_path() {
  case "$1" in
    "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# ask_yes_no <質問>
# Enter のみは Yes。入力が終わった（EOF）ときは No として扱う。
ask_yes_no() {
  local answer
  while true; do
    printf '%s [Y/n] ' "$1"
    if ! read -r answer; then
      echo
      return 1
    fi
    case "$answer" in
      "" | [Yy] | [Yy][Ee][Ss]) return 0 ;;
      [Nn] | [Nn][Oo]) return 1 ;;
      *) echo "y か n で答えてください" ;;
    esac
  done
}

# ask_input <質問> [デフォルト値]
# 入力値を標準出力に返す。Enter のみはデフォルト値。空にはできない。
ask_input() {
  local prompt="$1" default="${2:-}" answer
  while true; do
    if [ -n "$default" ]; then
      printf '%s [%s]: ' "$prompt" "$default" >&2
    else
      printf '%s: ' "$prompt" >&2
    fi
    read -r answer || return 1
    answer="${answer:-$default}"
    if [ -n "$answer" ]; then
      printf '%s\n' "$answer"
      return 0
    fi
    echo "値を入力してください" >&2
  done
}

# is_linked <リンク元> <リンク先>
is_linked() {
  [ -L "$2" ] && [ "$(readlink "$2")" = "$1" ]
}

# link_file <リンク元> <リンク先>
# リンク先に別のファイルがあれば、確認してから退避してリンクを作る。
link_file() {
  local src="$1" dest="$2" backup
  if is_linked "$src" "$dest"; then
    return 0
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    backup="$dest.backup-$(date +%Y%m%d%H%M%S)"
    ask_yes_no "$(pretty_path "$dest") が既にあります。$(pretty_path "$backup") に退避してリンクを作りますか？" || return 1
    mv "$dest" "$backup" || return 1
    ok "$(pretty_path "$backup") に退避しました"
  fi
  mkdir -p "$(dirname "$dest")" && ln -s "$src" "$dest" || return 1
  ok "$(pretty_path "$dest") -> $(pretty_path "$src")"
}

# has_block <ファイル> <名前>
has_block() {
  [ -f "$1" ] && grep -qF "# >>> $2 >>>" "$1"
}

# append_block <ファイル> <名前> <内容>
# マーカー付きのブロックを表示し、確認してからファイル末尾に追記する。
append_block() {
  local file="$1" name="$2" body="$3" block
  block="$(printf '# >>> %s >>>\n%s\n# <<< %s <<<' "$name" "$body" "$name")"
  echo "$(pretty_path "$file") の末尾に次の内容を追記します:"
  printf '%s\n' "$block" | sed 's/^/    /'
  ask_yes_no "追記しますか？" || return 1
  printf '\n%s\n' "$block" >>"$file" || return 1
  ok "$(pretty_path "$file") に追記しました"
}

# Homebrew のインストール先（Apple Silicon: /opt/homebrew, Intel: /usr/local）
brew_prefix() {
  if [ "$(uname -m)" = "arm64" ]; then
    echo /opt/homebrew
  else
    echo /usr/local
  fi
}

# PATH に brew がなければ、インストール先から読み込む
load_brew() {
  command -v brew >/dev/null 2>&1 && return 0
  local brew_bin
  brew_bin="$(brew_prefix)/bin/brew"
  [ -x "$brew_bin" ] || return 1
  eval "$("$brew_bin" shellenv)"
}
