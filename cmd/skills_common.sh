# Claude Code と Codex の plugin state の読み取りを共有する。
# caller は cmd/common.sh を source しておく。
# shellcheck shell=bash

# dotfiles marketplace から Claude Code と Codex にインストールする plugin。
DOTFILES_PLUGINS=(nozimin pstack)

claude_plugin_state() {
  local plugin_name="$1" json state
  if ! json="$(claude plugin list --json)"; then
    error "Claude Code の plugin 状態を確認できませんでした"
    return 1
  fi
  if ! state="$(printf '%s\n' "$json" | python3 -c '
import json, sys
try:
    plugins = json.load(sys.stdin)
    if not isinstance(plugins, list):
        raise ValueError("expected a list")
    state = "missing"
    for plugin in plugins:
        if plugin.get("id") == sys.argv[1] and plugin.get("scope") == "user":
            state = "enabled" if plugin.get("enabled") else "disabled"
            break
    print(state)
except Exception:
    sys.exit(1)
' "$plugin_name@dotfiles")"; then
    error "Claude Code の plugin 状態 JSON を解析できませんでした"
    return 1
  fi
  printf '%s\n' "$state"
}

codex_plugin_list_json() {
  codex plugin list --marketplace dotfiles --available --json || {
    error "Codex の plugin 状態を確認できませんでした"
    return 1
  }
}

codex_plugin_state_from_json() {
  local json="$1" plugin_name="$2" state
  if ! state="$(printf '%s\n' "$json" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    if not isinstance(data, dict) or not isinstance(data.get("installed"), list):
        raise ValueError("expected installed plugin list")
    state = "missing"
    for plugin in data["installed"]:
        if plugin.get("pluginId") == sys.argv[1]:
            state = "enabled" if plugin.get("enabled") else "disabled"
            break
    print(state)
except Exception:
    sys.exit(1)
' "$plugin_name@dotfiles")"; then
    error "Codex の plugin 状態 JSON を解析できませんでした"
    return 1
  fi
  printf '%s\n' "$state"
}

# Detect a known clone migration before querying a CLI whose old manifest may no longer load.
skills_repo_migration_pending() {
  local pointer="${HOME}/.config/dotfiles/repo" pointer_value
  { [ -e "${HOME}/.config/dotfiles/repo.migrating" ] || [ -L "${HOME}/.config/dotfiles/repo.migrating" ]; } && return 0
  pointer_value="$(skills_repo_pointer_value "$pointer")" || return 1
  case "$pointer_value" in
    /*) ;;
    *) return 1 ;;
  esac
  [ "$pointer_value" != "$REPO_ROOT" ]
}

# Match collect's repository pointer checks before setup reports skills ready.
skills_repo_pointer_is_usable() {
  skills_repo_pointer_matches "${HOME}/.config/dotfiles/repo" "$REPO_ROOT"
}

# cmd/setup uses the same state parsing as cmd/install_skills.
skills_setup_step() {
  local needs_install=0 have_cli=0 plugin_name plugin_state codex_json codex_home="${CODEX_HOME:-$HOME/.codex}" pointer="${HOME}/.config/dotfiles/repo"
  if skills_repo_migration_pending; then
    warn "clone 移動または未完了の skills 移行を検出しました。現在の clone から cmd/install_skills を実行してください"
    return 2
  fi
  if { [ -e "$pointer" ] || [ -L "$pointer" ]; } &&
    { [ ! -f "$pointer" ] || [ -L "$pointer" ]; }; then
    warn "$pointer は symlink または通常ファイル以外です。内容を確認し、必要なら退避して通常ファイルに直してから cmd/setup を再実行してください。自動では置き換えません"
    return 2
  fi
  if [ -f "$pointer" ] && ! skills_repo_pointer_value "$pointer" >/dev/null; then
    warn "$pointer を読み取れないか、1 行の repo path ではありません。権限と内容を確認して手動で修復してから cmd/setup を再実行してください"
    return 2
  fi
  if command -v claude >/dev/null 2>&1; then
    have_cli=1
    for plugin_name in "${DOTFILES_PLUGINS[@]}"; do
      plugin_state="$(claude_plugin_state "$plugin_name")" || return 1
      [ "$plugin_state" = enabled ] || needs_install=1
    done
  fi
  if command -v codex >/dev/null 2>&1; then
    have_cli=1
    if [ ! -d "$codex_home" ]; then
      needs_install=1
    else
      codex_json="$(codex_plugin_list_json)" || return 1
      for plugin_name in "${DOTFILES_PLUGINS[@]}"; do
        plugin_state="$(codex_plugin_state_from_json "$codex_json" "$plugin_name")" || return 1
        [ "$plugin_state" = enabled ] || needs_install=1
      done
    fi
  fi
  if [ "$have_cli" -eq 0 ]; then
    warn "Claude Code と Codex が見つからないため、skills をスキップしました"
    return 2
  fi
  if [ "$needs_install" -eq 0 ] && ! skills_repo_pointer_is_usable; then
    needs_install=1
  fi
  if [ "$needs_install" -eq 0 ]; then
    ok "利用可能な Agent の skills はインストール済み"
    return 0
  fi
  ask_yes_no "Agent Skills の登録と dotfiles repo pointer を確認・修復しますか？" || {
    warn "skills をスキップしました"
    return 2
  }
  "$REPO_ROOT/cmd/install_skills"
}
