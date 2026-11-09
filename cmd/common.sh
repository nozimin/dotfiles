# cmd/setup と cmd/install_brew から source する共通関数
# shellcheck shell=bash

# shellcheck disable=SC2034 # source 先で使う
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck disable=SC2034
LIB_DIR="$REPO_ROOT/lib"
# shellcheck disable=SC2034
MARKER="dotfiles"

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

# link_file <リンク元> <リンク先> [退避先のディレクトリ]
# 確認してからリンクを作る。別の場所へのリンクは張り替え、ファイルは退避する。
# 退避先のディレクトリを省略すると、リンク先と同じディレクトリに退避する。
# 確認で断られたら 2、退避やリンクの作成に失敗したら 1 を返す。
link_file() {
  local src="$1" dest="$2" backup_dir="${3:-$(dirname "$2")}" backup="" question
  if is_linked "$src" "$dest"; then
    return 0
  fi
  if [ -L "$dest" ]; then
    question="$(pretty_path "$dest") は $(pretty_path "$(readlink "$dest")") へのリンクです。$(pretty_path "$src") へのリンクに張り替えますか？"
  elif [ -e "$dest" ]; then
    backup="$backup_dir/$(basename "$dest").backup-$(date +%Y%m%d%H%M%S)"
    question="$(pretty_path "$dest") が既にあります。$(pretty_path "$backup") に退避して $(pretty_path "$src") へのリンクにしますか？"
  else
    question="$(pretty_path "$dest") を $(pretty_path "$src") へのリンクにしますか？"
  fi
  ask_yes_no "$question" || return 2
  if [ -n "$backup" ]; then
    mkdir -p "$backup_dir" && mv "$dest" "$backup" || return 1
    ok "$(pretty_path "$backup") に退避しました"
  elif [ -L "$dest" ]; then
    rm "$dest" || return 1
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

# replace_block <ファイル> <名前> <内容>
# マーカー付きのブロックの中身を、差分を表示して確認してから書き換える。
replace_block() {
  local file="$1" name="$2" body="$3" begin end tmp
  begin="# >>> $name >>>"
  end="# <<< $name <<<"
  echo "$(pretty_path "$file") の $name ブロックを書き換えます:"
  awk -v begin="$begin" -v end="$end" '$0 == end { f = 0 } f { print } $0 == begin { f = 1 }' "$file" | sed 's/^/    - /'
  printf '%s\n' "$body" | sed 's/^/    + /'
  ask_yes_no "書き換えますか？" || return 1
  tmp="$(mktemp)" || return 1
  if BODY="$body" awk -v begin="$begin" -v end="$end" '
    $0 == begin { print; print ENVIRON["BODY"]; f = 1; found = 1; next }
    $0 == end { f = 0 }
    !f { print }
    END { exit !found }
  ' "$file" >"$tmp" && cat "$tmp" >"$file"; then
    rm -f "$tmp"
    ok "$(pretty_path "$file") を書き換えました"
  else
    rm -f "$tmp"
    return 1
  fi
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
