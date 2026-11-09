# dotfiles

Mac の開発環境の設定ファイルと、それをセットアップするスクリプト。

## クイックスタート

新しい Mac で次を実行し、表示される質問に答える（Enter のみは Yes）。

```sh
git clone https://github.com/nozimin/dotfiles.git ~/WorkSpace/Repositories/dotfiles
~/WorkSpace/Repositories/dotfiles/cmd/setup
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

## ローカルの変更を取り込む

この Mac で入れたツールや `~/.zshrc` に書いた設定のうち、共通化したいものを dotfiles に取り込む（`cmd/setup` の逆向き）。dotfiles リポジトリで Claude Code を起動し、次を実行する。

```
/sync-to-dotfiles
```

- Brewfile、`~/.zshrc` / `~/.zprofile`、`lib/` の未コミットの変更について、dotfiles との差分が番号付きの表で出る。各項目のおすすめ（共通化／ローカル専用／保留）を見て、変えたい番号だけ答える。
- 選んだものを `lib/` に反映し、`main` に commit する。push するかは最後に確認される。
- ツールを新しく管理に加えたいときは、引数で伝える（例: `/sync-to-dotfiles VS Code も入れて`）。
- ツールを追加した後は `cmd/setup` を実行し直す。ほかの Mac では `git pull` してから実行する。

「ローカル専用」にした項目は除外リスト `~/.config/dotfiles/ignore` に追記され、次から表に出なくなる。Mac ごとのファイルで、リポジトリには入れない。

- 1 行に 1 つ、項目の `id` をそのまま書く。`id` は `<種類>:<識別子>` の形で、`.claude/skills/sync-to-dotfiles/scripts/collect` を実行すると見られる。
  - Brewfile の項目: 名前（`brew:actionlint`。サードパーティの tap のものは `brew:<user>/<tap>/<名前>` の完全な名前）
  - `~/.zshrc` / `~/.zprofile` の段落: コメントでない行を、前後の空白を除いて ` ⏎ `（前後に空白）でつないだもの（`zshrc:alias gcomi=...`、`zprofile:if command -v rbenv >/dev/null 2>&1; then ⏎ eval "$(rbenv init - zsh)" ⏎ fi`）。段落の中身が変わると `id` も変わり、また表に出る。
  - 秘密情報を含む段落: 上の文字列の SHA-256（`zshrc:sha256:<SHA-256>` のような形。秘密情報をファイルに書き写さないため）
  - `lib/` の変更: `lib:<リポジトリからの相対パス>`
- 空行と `#` で始まる行は無視される。
- 行を消すと、その項目はまた表に出る。

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
.claude/skills/sync-to-dotfiles/
  SKILL.md         /sync-to-dotfiles の手順（Claude Code が読む）
  scripts/collect  この Mac と dotfiles の差分を集める（読み取り専用）
```

## ツールを追加する

- **インストールだけ**: `lib/Brewfile` に `brew "<name>"` か `cask "<name>"` を1行足す。サードパーティの tap のものは `<user>/<tap>/<name>` の完全な名前で書く（短い名前だと、新しい Mac の `brew bundle` が失敗する）。
- **設定も必要**:
  1. 設定ファイルを `lib/` に置く。
  2. `cmd/setup` に `setup_<tool>` 関数を足し、末尾の手順の並びに呼び出しを足す。
     - 先に「済んでいるか」を判定し、済んでいれば `ok` を出して `return` する（冪等にする）。
     - 共通関数（`ask_yes_no` / `ask_input` / `link_file` / `append_block`）は `cmd/common.sh` にある。
  3. `lib/<tool>.md` にドキュメントを書き、上の表に1行足す。
- **シェルの設定（PATH や init）が必要**: `lib/zshrc` に書く。ツールがない環境でもエラーにならないよう `command -v <tool>` でガードする。
