# zsh

## setup がやること

`~/.zshrc` の末尾に、確認してから次のブロックを追記する。パスはリポジトリの場所から決まる。

```zsh
# >>> dotfiles >>>
source "/path/to/dotfiles/lib/zshrc"
# <<< dotfiles <<<
```

`~/.zshrc` 自体はマシンごとの実ファイルのまま残す。全マシン共通の設定は `lib/zshrc` に書き、マシン固有の設定は `~/.zshrc` に直接書く。

## `lib/zshrc` の中身

- `compinit` による補完（`brew shellenv` が `fpath` に追加した、brew で入れたコマンドの補完も有効になる）
- starship の初期化と、Enter のたびにプロンプトを再描画する `zle` 関数（右プロンプトの時刻を実行時刻にする）
- git のエイリアス

ツールの初期化は `command -v <tool>` でガードし、ツールがなくてもエラーにならないようにする。

## 手動でやる場合

```sh
printf '\n# >>> dotfiles >>>\nsource "%s/lib/zshrc"\n# <<< dotfiles <<<\n' "$(pwd)" >> ~/.zshrc
```

## リポジトリを移動したとき

移動先の `cmd/setup` を実行すると、`dotfiles` ブロックが古いパスを指していれば、差分を表示して書き換えるかを確認される。ブロックの外は変更しない。
