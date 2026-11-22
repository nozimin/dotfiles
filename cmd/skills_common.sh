# Claude Code と Codex の plugin state の読み取りを共有する。
# caller は cmd/common.sh を source しておく。
# shellcheck shell=bash

claude_plugin_state() {
  local json state
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
        if plugin.get("id") == "nozimin@dotfiles" and plugin.get("scope") == "user":
            state = "enabled" if plugin.get("enabled") else "disabled"
            break
    print(state)
except Exception:
    sys.exit(1)
')"; then
    error "Claude Code の plugin 状態 JSON を解析できませんでした"
    return 1
  fi
  printf '%s\n' "$state"
}

codex_plugin_state() {
  local json state
  if ! json="$(codex plugin list --marketplace dotfiles --available --json)"; then
    error "Codex の plugin 状態を確認できませんでした"
    return 1
  fi
  codex_plugin_state_from_json "$json"
}

codex_plugin_state_from_json() {
  local json="$1" state
  if ! state="$(printf '%s\n' "$json" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    if not isinstance(data, dict) or not isinstance(data.get("installed"), list):
        raise ValueError("expected installed plugin list")
    state = "missing"
    for plugin in data["installed"]:
        if plugin.get("pluginId") == "nozimin@dotfiles":
            state = "enabled" if plugin.get("enabled") else "disabled"
            break
    print(state)
except Exception:
    sys.exit(1)
')"; then
    error "Codex の plugin 状態 JSON を解析できませんでした"
    return 1
  fi
  printf '%s\n' "$state"
}

# cmd/setup uses the same state parsing as cmd/install_skills.
skills_setup_step() {
  local needs_install=0 have_cli=0 plugin_state codex_home="${CODEX_HOME:-$HOME/.codex}"
  if command -v claude >/dev/null 2>&1; then
    have_cli=1
    plugin_state="$(claude_plugin_state)" || return 1
    [ "$plugin_state" = enabled ] || needs_install=1
  fi
  if command -v codex >/dev/null 2>&1; then
    have_cli=1
    if [ ! -d "$codex_home" ]; then
      plugin_state=missing
    else
      plugin_state="$(codex_plugin_state)" || return 1
    fi
    [ "$plugin_state" = enabled ] || needs_install=1
  fi
  if [ "$have_cli" -eq 0 ]; then
    warn "Claude Code と Codex が見つからないため、skills をスキップしました"
    return 2
  fi
  if [ "$needs_install" -eq 0 ]; then
    ok "利用可能な Agent の skills はインストール済み"
    return 0
  fi
  ask_yes_no "Claude Code と Codex に dotfiles の skills をインストールしますか？" || {
    warn "skills をスキップしました"
    return 2
  }
  "$REPO_ROOT/cmd/install_skills"
}
