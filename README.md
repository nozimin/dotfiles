# config_for_mac

Mac の開発環境の設定ファイルと、それをセットアップするスクリプト。

## クイックスタート

新しい Mac で次を実行し、表示される質問に答える（Enter のみは Yes）。

```sh
git clone https://github.com/nozimin/config_for_mac.git ~/WorkSpace/Repositories/config_for_mac
~/WorkSpace/Repositories/config_for_mac/cmd/setup
```

- `git clone` の初回は Xcode Command Line Tools のインストールダイアログが出るので、インストールしてからやり直す。
- clone 先はどこでもよい。スクリプトは自分の場所からリポジトリを探す。
- iTerm2 の設定を変えるため、Terminal.app から実行する。
- 何度実行してもよい。済んでいる手順は質問せずにスキップする。

## `cmd/setup` がやること

| 手順 | 内容 | ドキュメント |
|---|---|---|
| Homebrew | 未インストールなら `cmd/install_brew` でインストールし、`~/.zprofile` に `brew shellenv` を追記する | [lib/homebrew.md](lib/homebrew.md) |
| Brewfile | `lib/Brewfile` のうち未インストールのものを表示し、`brew bundle` でインストールする | [lib/homebrew.md](lib/homebrew.md) |
| zsh | `~/.zshrc` の末尾に `lib/zshrc` を読み込む行を追記する | [lib/zsh.md](lib/zsh.md) |
| starship | `~/.config/starship.toml` を `lib/starship.toml` へのシンボリックリンクにする | [lib/starship.md](lib/starship.md) |
| iTerm2 | iTerm2 が `lib/com.googlecode.iterm2.plist` を読み込み、変更を自動で保存するようにする | [lib/iterm2.md](lib/iterm2.md) |
| GitHub (gh) | `gh auth login` でログインし、`gh auth setup-git` で git の認証に gh を使う | [lib/git.md](lib/git.md) |
| git | `user.name` と `user.email` が未設定なら入力してもらう | [lib/git.md](lib/git.md) |

`~/.zshrc` などへの追記や、既存ファイルの退避は、内容を表示して確認してから行う。最後にスキップしたものと失敗したものを表示する。失敗があれば終了コードは 1。

## リポジトリを移動したとき

`~/.zshrc` の source 行、`~/.config/starship.toml` のリンク、iTerm2 の設定フォルダは、リポジトリの絶対パスを指している。移動したら、移動先の `cmd/setup` を実行し直す。古い場所を指しているものごとに、書き換えるかを確認される。

iTerm2 の手順は iTerm2 を終了しないと実行できないので、Terminal.app から実行する。

## 構成

```
cmd/
  setup          セットアップ本体
  install_brew   Homebrew のインストール（単体でも実行できる）
  common.sh      共通関数（setup と install_brew から source する）
lib/
  Brewfile                     brew bundle でインストールするもの
  zshrc                        共通の zsh 設定（~/.zshrc から source する）
  starship.toml                starship の設定
  com.googlecode.iterm2.plist  iTerm2 の設定
  *.md                         各ツールのドキュメント
```

## ツールを追加する

- **インストールだけ**: `lib/Brewfile` に `brew "<name>"` か `cask "<name>"` を1行足す。
- **設定も必要**:
  1. 設定ファイルを `lib/` に置く。
  2. `cmd/setup` に `setup_<tool>` 関数を足し、末尾の手順の並びに呼び出しを足す。
     - 先に「済んでいるか」を判定し、済んでいれば `ok` を出して `return` する（冪等にする）。
     - 共通関数（`ask_yes_no` / `ask_input` / `link_file` / `append_block`）は `cmd/common.sh` にある。
  3. `lib/<tool>.md` にドキュメントを書き、上の表に1行足す。
- **シェルの設定（PATH や init）が必要**: `lib/zshrc` に書く。ツールがない環境でもエラーにならないよう `command -v <tool>` でガードする。
