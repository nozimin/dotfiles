# iTerm2

Brewfile の `cask "iterm2"` でインストールする。

## setup がやること

iTerm2 が `lib/com.googlecode.iterm2.plist` を読み込み、設定の変更を自動でそこに保存するようにする。

```sh
defaults write com.googlecode.iterm2 PrefsCustomFolder -string "<repo>/lib"
defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true
defaults write com.googlecode.iterm2 NoSyncNeverRemindPrefsChangesLostForFile -bool true
defaults write com.googlecode.iterm2 NoSyncNeverRemindPrefsChangesLostForFile_selection -int 2
```

- `NoSyncNeverRemindPrefsChangesLostForFile_selection` の値は `0`: 終了時に保存、`1`: 保存しない、`2`: 自動で保存。
- iTerm2 の起動中に書き換えると、iTerm2 が終了時に設定を書き戻すことがある。そのため起動中は書き換えずに失敗として表示する。iTerm2 を終了してから、Terminal.app で再実行する。

## 手動でやる場合

iTerm2 の Settings → General → Settings で次の2つを設定する。

- 「Load settings from a custom folder or URL」にチェックを入れ、`<repo>/lib` を指定する。
- 「Save changes」を「Automatically」にする。

## 注意

自動保存にしているので、iTerm2 で設定を変えると `lib/com.googlecode.iterm2.plist` に差分が出る。変更を残したいときはコミットする。
