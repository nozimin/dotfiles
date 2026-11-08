# sync-to-dotfiles 仕様書

この Mac の設定と dotfiles リポジトリの差分を集め、共通化したいものだけを dotfiles に取り込む Claude Code の skill。
`cmd/setup`（dotfiles → この Mac）と逆向きの入口。

## 1. 範囲

- 見るのは、dotfiles が既に管理している範囲だけ（§4）。skill が自分で新しい候補を探すことはしない。
- 新しいツールを管理に加えるのは、ユーザーが引数か会話で頼んだときだけ（§9）。
- 範囲外: npm のグローバルパッケージ、macOS の defaults、`~/.ssh/config`、`~/.rbenv/version`、`~/.config/gh/config.yml`、Claude Code の設定（ユーザーが §9 で頼めば追加できる）。
- VS Code は、この skill を main に入れた後の最初の実行で §9 の手順で取り込む。この skill の実装には含めない。

## 2. ファイル構成

```
.claude/skills/sync-to-dotfiles/
  SKILL.md         流れ、判断のルール、表の出し方、反映の手順
  scripts/collect  差分を集めて決まった形式で出す（bash、実行権限付き）
```

- 言語は日本語（SKILL.md、collect のコメントとメッセージ）。既存の `cmd/setup` と `cmd/common.sh` の書き方に合わせる。
- `collect` は読み取り専用。書き込みは `git fetch` だけ。ファイルの編集、commit、push は SKILL.md の手順で Claude が行う。

## 3. 起動

- frontmatter: `name: sync-to-dotfiles`、`disable-model-invocation: true`、`argument-hint`（例: `[追加したいツール]`）、description は日本語。
- `/sync-to-dotfiles` で手動起動したときだけ動く。dotfiles リポジトリで Claude Code を起動して使う。
- 引数（任意）: 管理に加えたいツール（例: `/sync-to-dotfiles VS Code も入れて`）。引数なしなら差分の確認だけ。

## 4. collect が集めるもの

| 種類 (`kind`) | ローカル側 | dotfiles 側 |
|---|---|---|
| `brew` | `brew leaves --installed-on-request` | `lib/Brewfile` の `brew "..."` |
| `cask` | `brew list --cask` | `lib/Brewfile` の `cask "..."` |
| `tap` | `brew tap` | `lib/Brewfile` の `tap "..."` |
| `zshrc` | `~/.zshrc` の dotfiles ブロックの外 | `lib/zshrc` |
| `zprofile` | `~/.zprofile` の dotfiles ブロックの外 | `lib/zshrc` |
| `lib` | リポジトリの `lib/` 以下の未コミットの変更（未追跡のファイルを含む） | `HEAD` |

- brew コマンドは `HOMEBREW_NO_AUTO_UPDATE=1` で呼ぶ。brew が無ければ `brew` `cask` `tap` を飛ばし、`warn` を出す。
- 逆向きの差分も出す: Brewfile にあるのにインストールされていないもの。`brew` はインストール済みかを `brew list --formula`（依存として入ったものも含む）で判定する。
- dotfiles ブロック: `# >>> dotfiles` で始まる行から `# <<< dotfiles` で始まる行まで（`dotfiles: homebrew` のような名前付きも含む）。
- `zprofile` では `brew shellenv` を含む行も除く（dotfiles ブロック導入前に追記されたもの）。
- `zshrc` と `zprofile` は、空行で区切った「段落」を 1 項目にする。コメントだけの段落と空の段落は出さない。
- VS Code の拡張機能（Brewfile の `vscode` 行）は、VS Code を §9 で取り込むときに collect に追加する。今は扱わない。

## 5. collect の出力形式

標準出力に次のブロックを順に出す。Claude が読む前提なので、毎回同じ形式にする。

```
=== repo
branch: main
behind: 0
ahead: 0
dirty: README.md
=== item
kind: brew
id: brew:actionlint
direction: local
flags: -
body:
    actionlint
=== item
kind: zshrc
id: zshrc:alias gcomi='(){~/Script/cmd/commit $1}'
direction: local
flags: missing-path
body:
    alias gcomi='(){~/Script/cmd/commit $1}'
=== warn
brew が見つからないため、brew / cask / tap を確認していません
=== summary
items: 12
ignored: 1
```

- `=== repo`: `branch` は現在のブランチ。`behind` と `ahead` は `origin/<branch>` との差のコミット数。fetch に失敗したら `unknown`。`dirty` は `lib/` 以外の未コミットの変更（未追跡を含む）で、1 ファイル 1 行、無ければ行を出さない。
- `=== item`: 差分 1 件。
  - `kind`: §4 の種類。
  - `id`: 除外リスト（§7）で使う識別子。`<kind>:<識別子>` の形。`brew` `cask` `tap` は名前、`zshrc` `zprofile` は段落の最初のコメントでない行、`lib` はリポジトリからの相対パス。
  - `direction`: `local`（ローカルにだけある）、`dotfiles`（dotfiles にだけある）、`changed`（`lib/` の未コミットの変更）のどれか。
  - `flags`: §6 のフラグをカンマ区切りで。無ければ `-`。
  - `body:` の後: 本文。各行の先頭に 4 スペースを付ける。`brew` `cask` `tap` は名前、`zshrc` `zprofile` は段落の全文、`lib` は §5.1 の要約。
- `=== warn`: 確認できなかったこと（1 行 1 件）。無ければブロックを出さない。
- `=== summary`: `items`（出した項目数）と `ignored`（除外リストで除いた数）。
- オプション: `--no-fetch`（`git fetch` しない。`behind` と `ahead` はローカルの追跡ブランチで数える）。
- テストのために `HOME` と `PATH` を差し替えて動くようにする（`~` は `$HOME` で解決し、brew は `PATH` から探す）。除外リストの場所は環境変数 `DOTFILES_IGNORE_FILE` で差し替えられる。
- リポジトリの場所は collect 自身の場所から求める（`.claude/skills/sync-to-dotfiles/scripts/` の 4 つ上）。
- 終了コード: 出力できたら 0。リポジトリが見つからないなど、出力できなかったら 1。

### 5.1 `lib` の要約

- `.plist`: 変わったキーのパスと、前後の値（80 文字を超える値は省略）。`HEAD` の内容と作業ツリーの内容を比べる。
- それ以外: `git diff` の内容（200 行を超えたら省略し、省略したことを書く）。未追跡のファイルは先頭 200 行。

## 6. フラグ

| フラグ | 条件 | skill のおすすめ |
|---|---|---|
| `home-path` | `$HOME` の絶対パス（`/Users/<ユーザー名>/...`）を含む | 共通化。取り込むときに `$HOME` か `~` に書き換える |
| `missing-path` | `~/...`、`$HOME/...`、`${HOME}/...`、`/Users/...` のパスで、存在しないものを参照している | ローカル専用 |
| `secret` | トークンらしい文字列を含む（`token` `secret` `password` `passwd` `api_key` `apikey` への代入、`ghp_` `gho_` `github_pat_` `sk-` `xox?-` `AKIA` で始まる値など） | 共通化を選べない。ローカル専用か保留だけ |
| `garbage` | 1000 文字以上の行、または 100 文字以上の空白だけの行がある | 取り込むときにその行を消す |
| `in-dotfiles` | 段落のコメントでない行が、すべて `lib/zshrc` に既にある（前後の空白を除いて比べる） | 共通化（dotfiles にあるので、ローカルから消すだけ） |

複数のフラグが立ったときは `secret` > `in-dotfiles` > `missing-path` > `home-path` の順に優先する。`garbage` は、おすすめとは別に「取り込むときにその行を消す」という但し書きとして扱う。

## 7. 除外リスト

- 場所: `~/.config/dotfiles/ignore`。Mac ごとに持ち、リポジトリには入れない。
- 形式: 1 行に 1 つ、§5 の `id` をそのまま書く。空行と `#` で始まる行は無視する。
- collect は、`id` が完全に一致する項目を出さず、`ignored` に数える。ファイルが無ければ除外なしとして扱う。
- skill は、ユーザーが「ローカル専用」にした項目の `id` を `${DOTFILES_IGNORE_FILE:-$HOME/.config/dotfiles/ignore}` に追記する（ディレクトリが無ければ作る）。

## 8. skill の流れ

§9 のツールの追加を頼まれたときは、1〜4 → §9 → 5 の順に行い、push の確認は最後に 1 回だけにする。

1. **開始時の確認**: `collect` を実行する。
   - `branch` が `main` でなければ止める。
   - `dirty` があれば止め、そのファイルを伝える。
   - `behind` が 1 以上なら、AskUserQuestion で `git pull --ff-only` するかを聞き（おすすめは pull する）、pull したら `collect` を実行し直す。pull しないと答えたら、最後の push が拒否されうることを伝えて続ける。`pull --ff-only` が失敗したら（分岐しているとき）止めて伝える。
   - `behind` が `unknown` なら、そのことを伝えて続けるかを聞く。
   - `ahead` が 1 以上なら、そのコミットも最後の push に含まれることを伝える。
2. **表で選んでもらう**: 項目をエリア（Brewfile、zsh、`lib/` の変更、逆向きの差分）ごとに番号付きの表にする。各項目に、おすすめ（共通化／ローカル専用／保留）と理由を付ける。ユーザーは変えたい番号だけ答える。
   - おすすめは §6 のフラグに従う。フラグが無い項目は、内容から Claude が判断する。
   - `secret` の項目は共通化を選べない。
   - 逆向きの差分（`direction: dotfiles`）は別セクションにし、選択肢は「残す」（デフォルト）と「dotfiles から削除」。
   - `lib` の項目は「commit／破棄（`git restore`）／保留」。
   - 項目が 0 件なら、そう伝えて終わる（§9 の依頼があればそちらに進む）。
3. **反映**:
   - Brewfile: 既存のセクション（`# CLI`、`# アプリ`、`# フォント`）の適切な場所に足す。合うものが無ければセクションを足す。「dotfiles から削除」は行を消す。
   - zsh: `lib/zshrc` に足す。ツールに依存する行は `command -v <tool>` でガードする（README の約束）。`home-path` は `$HOME` か `~` に書き換え、`garbage` の行は消す。`zprofile` から取り込むものも `lib/zshrc` に入れる（`lib/zprofile` は作らない）。
   - 取り込んだ（または `in-dotfiles` だった）段落は、ローカルの `~/.zshrc` / `~/.zprofile` から消す。消す前に差分を見せて確認し、`<ファイル>.backup-YYYYmmddHHMMSS` に退避する。
   - `lib` の「破棄」は `git restore`（未追跡なら削除）。iTerm2 の plist は、iTerm2 が起動中だと終了時に書き戻されることを伝える。
   - 「ローカル専用」は除外リストに追記する。「保留」は何もしない（次回また出る）。
4. **commit**: `git diff` を見せて確認してから、エリアごとに分けて `main` に直接 commit する（個人用の dotfiles なのでブランチや PR は作らない）。メッセージは `[feat]` `[fix]` `[del]` + 日本語（例: `[feat] Brewfile に actionlint などを追加`）。
5. **push**: AskUserQuestion で `origin main` に push するかを聞く。おすすめは「push する」。

## 9. ツールの追加

ユーザーが引数か会話でツールの追加を頼んだときだけ行う。§8 の差分の確認の後に行う。

1. README の「ツールを追加する」の手順で行う: 設定ファイルを `lib/` に置く、`cmd/setup` に冪等な `setup_<tool>` を足して手順の並びに加える、`lib/<tool>.md` を書く、README の表に 1 行足す。
2. 反映方法をツールごとに提案し、確認する:
   - 原則はシンボリックリンク（設定ファイルを `lib/` にコピーし、元のファイルは `cmd/setup` の `link_file` が退避してリンクにする。starship と同じ）。以後のローカルの変更は `lib` の未コミットの変更として §8 で出てくる。
   - Mac ごとの値や秘密情報が混ざるファイルは、ツールの include 機能を使う（例: git は `~/.gitconfig` に `[include] path = .../lib/gitconfig`）。シンボリックリンクにすると、秘密情報を除いた内容でローカルのファイルが置き換わるため。
   - ツールがシンボリックリンクを保つか（書き換えるときにリンクを普通のファイルに置き換えないか）を確かめ、保たないなら別の方式にする。
3. include 方式のように `lib` の変更として出てこないものは、そのツール用の検出を `collect` に足す（§5 の形式で出す）。
4. 秘密情報（§6 の `secret`）と壊れた内容（`garbage`）は取り込まない。
5. ユーザーに別のターミナル（Terminal.app）で `<リポジトリ>/cmd/setup` を実行してもらい（Claude Code の `!` では `cmd/setup` の質問に答えられないため）、ローカルのファイルがリンクなどに切り替わったことを Claude が確認してから、§8 の 4、5 で commit と push をする。

## 10. README

「ローカルの変更を取り込む」節を足す:

- dotfiles リポジトリで Claude Code を起動し、`/sync-to-dotfiles` を実行する。ツールを管理に加えたいときは引数で伝える。
- 除外リストの場所（`~/.config/dotfiles/ignore`）と形式。
- 新しいツールを追加した後は `cmd/setup` を実行し直す。

「構成」に `.claude/skills/sync-to-dotfiles/` を足す。

## 11. 受け入れ条件

1. この Mac で `collect --no-fetch` を実行すると、少なくとも次が出る:
   - `brew`: `actionlint` `flyctl` `mysql` `node` `rbenv` `uv`（`direction: local`）
   - `cask`: `postman` `unity-hub`（`direction: local`）
   - `zshrc`: `eval "$(rbenv init - zsh)"` の段落と、`alias gcomi=...` の段落（`flags: missing-path`）
   - `zprofile`: `rbenv init` の段落（`brew shellenv` の行は出ない）
   - Brewfile に既にある `git` `gh` `starship` などは出ない
2. 一時的な `HOME` と偽の `brew` を使ったテストで、逆向きの差分、除外リスト、各フラグ、`lib` の plist の要約、`dirty` が期待どおりに出る。
3. `collect` を実行しても、`git fetch` 以外に何も書き換えない。
4. `shellcheck` が警告なしで通る。
5. SKILL.md が §3、§8、§9 をすべて手順として含み、§5 の形式を前提に書かれている。
6. README に §10 の内容がある。
