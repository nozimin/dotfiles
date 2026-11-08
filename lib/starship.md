# starship

[starship](https://starship.rs/) はシェルのプロンプト。Brewfile の `brew "starship"` でインストールする。

## setup がやること

- `~/.config/starship.toml` を `lib/starship.toml` へのシンボリックリンクにする。
- すでに別のファイルがあれば、確認してから `starship.toml.backup-<日時>` に退避する。
- 別の場所へのリンク（リポジトリを移動した場合など）なら、確認してから張り替える。

starship の初期化は `lib/zshrc` に書いてある（[zsh.md](zsh.md)）。

## 手動でやる場合

```sh
brew install starship
brew install --cask font-fira-code-nerd-font
mkdir -p ~/.config
ln -s "$(pwd)/lib/starship.toml" ~/.config/starship.toml
```

## フォント

`lib/starship.toml` は Nerd Font の記号（ブランチや OS のアイコン）を使う。

- フォントは FiraCode Nerd Font を使う。Brewfile の `cask "font-fira-code-nerd-font"` で入る。
- iTerm2 の設定（`lib/com.googlecode.iterm2.plist`）は、このフォント（`FiraCodeNF-Reg 14`）を使うようになっている。

## カスタマイズ

`lib/starship.toml` を直接編集する。シンボリックリンクなので、次のプロンプトからすぐ反映される。設定項目は [Configuration](https://starship.rs/config/) を参照。
