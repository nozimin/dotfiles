# cmd/install_skills と Agent Skill の書き込みで共有する macOS 対応 lock。
# caller は CONFIG_DIR、INSTALL_LOCK_DIR、LOCK_HELD を設定し、cmd/common.sh を source する。
# shellcheck shell=bash

skills_lock_acquire() {
  local lock_host owner_pid owner_host attempts
  mkdir -p "$CONFIG_DIR" || {
    error "$CONFIG_DIR を作成できませんでした"
    return 1
  }
  lock_host="$(hostname)" || {
    error "lock 用の host 名を取得できませんでした"
    return 1
  }
  while ! mkdir "$INSTALL_LOCK_DIR" 2>/dev/null; do
    if [ ! -d "$INSTALL_LOCK_DIR" ] || [ -L "$INSTALL_LOCK_DIR" ]; then
      error "$INSTALL_LOCK_DIR は lock directory ではありません。内容を確認し、別の installer が動作していないことを確認してから手動で整理してください"
      return 1
    fi
    if [ ! -f "$INSTALL_LOCK_DIR/owner" ]; then
      attempts=0
      while [ "$attempts" -lt 10 ] && [ ! -f "$INSTALL_LOCK_DIR/owner" ]; do
        sleep 0.1
        attempts=$((attempts + 1))
      done
      if [ ! -f "$INSTALL_LOCK_DIR/owner" ]; then
        error "$INSTALL_LOCK_DIR に owner 情報がありません。別 installer の起動中なら少し待って再実行し、起動中でない場合は lock directory を手動で削除してから再試行してください"
        return 1
      fi
    fi
    owner_pid="$(sed -n '1p' "$INSTALL_LOCK_DIR/owner")"
    owner_host="$(sed -n '2p' "$INSTALL_LOCK_DIR/owner")"
    case "$owner_pid" in
      ''|0|*[!0-9]*)
        error "$INSTALL_LOCK_DIR/owner が不正です。installer が実行中でないことを確認し、lock directory を手動で削除してから再実行してください"
        return 1
        ;;
    esac
    if [ "$owner_host" != "$lock_host" ]; then
      error "$INSTALL_LOCK_DIR は別 host ($owner_host) の lock です。共有 HOME の場合は所有 host で installer が終了したことを確認してください。lock を自動では削除しません"
      return 1
    fi
    if kill -0 "$owner_pid" 2>/dev/null; then
      error "別の skills installer または書き込み処理が実行中です (pid $owner_pid, host $owner_host)"
      return 1
    fi
    error "skills installer の stale lock を検出しました (pid $owner_pid, host $owner_host)。その処理が終了したことを確認し、次を実行してから再試行してください: rm -rf '$INSTALL_LOCK_DIR'"
    return 1
  done
  if ! printf '%s\n%s\n' "$$" "$lock_host" >"$INSTALL_LOCK_DIR/owner"; then
    error "$INSTALL_LOCK_DIR に owner 情報を書き込めませんでした。lock を確認してください"
    return 1
  fi
  LOCK_HELD=1
}

skills_lock_release() {
  if [ "${LOCK_HELD:-0}" -eq 1 ] && [ "$(sed -n '1p' "$INSTALL_LOCK_DIR/owner" 2>/dev/null)" = "$$" ]; then
    rm -rf "$INSTALL_LOCK_DIR"
    LOCK_HELD=0
  fi
}

# 子 installer が setup の lock を借りる場合、owner PID/host と live lock を再確認する。
skills_lock_is_owned_by() {
  local expected_pid="$1" lock_host owner_pid owner_host
  [ -d "$INSTALL_LOCK_DIR" ] && [ ! -L "$INSTALL_LOCK_DIR" ] &&
    [ -f "$INSTALL_LOCK_DIR/owner" ] && [ ! -L "$INSTALL_LOCK_DIR/owner" ] || return 1
  owner_pid="$(sed -n '1p' "$INSTALL_LOCK_DIR/owner")"
  owner_host="$(sed -n '2p' "$INSTALL_LOCK_DIR/owner")"
  case "$expected_pid" in
    ''|0|*[!0-9]*) return 1 ;;
  esac
  [ "$owner_pid" = "$expected_pid" ] && [ "$owner_host" = "$(hostname)" ] && kill -0 "$expected_pid" 2>/dev/null
}
