# Homebrew

## setup がやること

1. `brew` がなければ、確認してから公式のインストーラを実行する（`cmd/install_brew`）。途中で Enter とパスワードの入力を求められる。
2. `~/.zprofile` に `brew shellenv` を含む行がなければ、確認してから次を追記する。

   ```zsh
   # >>> config_for_mac: homebrew >>>
   eval "$(/opt/homebrew/bin/brew shellenv)"
   # <<< config_for_mac: homebrew <<<
   ```

   Intel Mac では `/usr/local/bin/brew` になる。
3. `lib/Brewfile` のうち未インストールのものを表示し、確認してから `brew bundle install --no-upgrade` を実行する。インストール済みのものはアップグレードしない。

`cmd/install_brew` は単体でも実行できる。

## 手動でやる場合

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"

brew bundle install --file=lib/Brewfile --no-upgrade
```

## Brewfile を編集する

```sh
brew bundle check --file=lib/Brewfile --verbose   # 未インストールのものを表示
brew bundle add --file=lib/Brewfile <name>        # formula を追加（cask は --cask）
```

あるマシンで入れたくないものは、`lib/Brewfile` の行をコメントアウトする。

- FiraCode Nerd Font（`font-fira-code-nerd-font`）は starship の記号表示に必要。
- `~/Library/Fonts` に同じフォントを手動で入れていると、cask のインストールが「already a Font at ...」で失敗する。手動で入れたものを削除してから再実行する。
