---
name: sync-to-dotfiles
description: この Mac の設定と dotfiles の差分を表で見せ、選んだものを dotfiles に取り込む。引数で伝えたツールを管理に加える。
disable-model-invocation: true
---

# sync-to-dotfiles

この Mac の Homebrew のパッケージ、`~/.zshrc` / `~/.zprofile`、`lib/` の未コミットの変更を dotfiles と比べ、ユーザーが選んだものを dotfiles に取り込む。`cmd/setup`（dotfiles → この Mac）の逆向き。

- 扱うのは `collect` が出す差分だけ。新しいツールを管理に加えるのは、起動時の引数か会話でユーザーが頼んだときだけ（「ツールの追加」）。
- commit は `main` に直接行う。個人用の dotfiles なので、ブランチも PR も作らない（ユーザーが決めたこと）。
- コマンドはリポジトリのルートで実行する。

## collect の出力

`.claude/skills/sync-to-dotfiles/scripts/collect` は差分を標準出力に出す。読み取り専用で、書き込むのは `git fetch` だけ。`--no-fetch` を付けると fetch しない。終了コード 1 は、出力できなかったことを表す。

出力は `=== <名前>` で始まるブロックの並び:

- `=== repo`: `branch`、`behind` / `ahead`（`origin/<branch>` との差のコミット数。fetch に失敗したら `unknown`）、`dirty`（`lib/` 以外の未コミットの変更。1 ファイル 1 行。無ければ行が無い）。
- `=== item`: 差分 1 件。
  - `kind`: `brew` `cask` `tap`（Brewfile）、`zshrc` `zprofile`（dotfiles ブロックの外の段落）、`lib`（`lib/` の未コミットの変更）。
  - `id`: 除外リストに書く識別子。`id: ` の後ろの全体。
  - `direction`: `local`（ローカルにだけある）、`dotfiles`（Brewfile にあるのに未インストール）、`changed`（`lib/` の変更）。
  - `flags`: カンマ区切り。無ければ `-`。意味は「おすすめの決め方」。
  - `body:` の後の行: 本文。各行の先頭の 4 スペースを外すと元の行になる。`zshrc` `zprofile` は段落の全文、`lib` は変更の要約（plist は変わったキーのパスと前後の値）。
- `=== warn`: 確認できなかったこと。1 行 1 件。
- `=== summary`: `items`（項目数）と `ignored`（除外リストで除いた数）。

## 流れ

### 1. 開始時の確認

`collect` を実行する。終了コード 1 なら、エラーを伝えて止める。`=== repo` を見る:

- `branch` が `main` でなければ止め、`main` で起動し直すよう伝える。
- `dirty` があれば止め、そのファイルを伝える（commit か破棄をしてから起動し直す）。
- `behind` が 1 以上なら、AskUserQuestion で `git pull --ff-only` するかを聞く。おすすめは「pull する」。
  - pull したら `collect --no-fetch` を実行し直し、その出力で続ける。
  - pull が失敗したら（ローカルと origin が分岐しているなど）、止めて伝える。
  - pull しないなら、最後の push が拒否されうることを伝えて続ける。
- `behind` が `unknown` なら、origin と比べられなかったことを伝え、AskUserQuestion で続けるかを聞く。
- `ahead` が 1 以上なら、push していない commit があり、最後の push に含まれることを伝える。

`branch` が `main` で `dirty` が無く、pull の判断まで済んだ `collect` の出力が手元にあれば、次に進む。

### 2. 表で選んでもらう

先に `=== warn` の内容と、除外リストで除いた数（`ignored`）を伝える。項目が 0 件なら、差分が無いことを伝えて終わる（ツールの追加を頼まれていれば「ツールの追加」に進む）。

項目をエリアごとの表にする。番号はエリアをまたいで通し番号にする。

| エリア | 項目 | 選択肢 |
|---|---|---|
| Brewfile | `brew` `cask` `tap` で `direction: local` | 共通化／ローカル専用／保留 |
| zsh | `zshrc` `zprofile` | 共通化／ローカル専用／保留 |
| `lib/` の変更 | `lib` | commit／破棄（`git restore`）／保留 |
| 逆向きの差分 | `direction: dotfiles` | 残す（デフォルト）／dotfiles から削除 |

- 表の列は「#、項目、おすすめ、理由」。フラグがあれば理由に書く。
- zsh と `lib/` の項目は、表の下に番号ごとの本文をコードブロックで見せる。長い `lib` の要約は抜粋し、残りは聞かれたら見せる。
- 最後に「変えたい番号と選択肢だけ答えてください（例: `3 保留, 7 ローカル専用`）。すべておすすめどおりなら OK」と書き、ターンを終えて返事を待つ。

```markdown
**Brewfile**

| # | 項目 | おすすめ | 理由 |
|---|---|---|---|
| 1 | brew `actionlint` | 共通化 | GitHub Actions の lint。どの Mac でも使う |

**zsh**

| # | 項目 | おすすめ | 理由 |
|---|---|---|---|
| 2 | `~/.zshrc` の `alias gcomi=...`（1 行） | ローカル専用 | `missing-path`: `~/Script/cmd/commit` が無い |
```

`secret` の項目を共通化にしたいと言われたら、秘密情報が入るので選べないことを伝え、ローカル専用か保留から選んでもらう。

すべての項目の選択が決まったら、次に進む。

#### おすすめの決め方

フラグが複数あれば、表の上にあるものを優先する。

| フラグ | 意味 | おすすめ |
|---|---|---|
| `secret` | トークンらしい文字列がある | ローカル専用（共通化は選べない。ローカル専用か保留だけ） |
| `in-dotfiles` | 段落のコメントでない行が、すべて `lib/zshrc` に既にある | 共通化（dotfiles にあるので、ローカルから消すだけ） |
| `missing-path` | 存在しないパスを参照している | ローカル専用 |
| `home-path` | `/Users/<ユーザー名>/...` を含む | 共通化。取り込むときに `$HOME` か `~` に書き換える |
| `garbage` | 1000 文字以上の行か、空白だけの長い行がある | ほかの条件で決め、取り込むときにその行を消す |

フラグが無い項目は内容から決める:

- どの Mac でも使う開発ツールや設定は共通化。特定の案件やこの Mac の事情によるものはローカル専用。判断がつかなければ保留。
- 関連する項目（`rbenv` の brew と `rbenv init` の段落など）は、おすすめを揃える。
- `lib` は、意図した設定の変更なら commit。判断がつかなければ保留。
- 逆向きの差分は「残す」。

### 3. 反映

選択ごとに次を行う。リポジトリのファイルを先に変え、ローカルのファイルはその後に変える。

- **共通化（Brewfile）**: `lib/Brewfile` の合うセクションの末尾に `brew "<名前>"` / `cask "<名前>"` / `tap "<名前>"` を足す。formula は `# CLI`、アプリの cask は `# アプリ`、フォントの cask は `# フォント`。合うセクションが無ければ（`tap` など）コメント付きのセクションを足す。`tap` のセクションは先頭に置く。
- **dotfiles から削除**: `lib/Brewfile` からその行を消す。
- **共通化（zsh）**: 段落を `lib/zshrc` に足す。
  - 既存のコメント付きのまとまり（`# 補完`、`# starship`、`# Alias`）の合うところに足す。合うものが無ければ、コメント付きのまとまりを足す。
  - ツールに依存する行は、starship のまとまりと同じ `if command -v <tool> >/dev/null 2>&1; then ... fi` でガードする（README の約束）。
  - `home-path` の行は `/Users/<ユーザー名>` を `$HOME` か `~` に書き換える。引用符の中では `~` が展開されないので `$HOME` にする。
  - `garbage` の行は消す。
  - `zprofile` の段落も `lib/zshrc` に入れる（`lib/zprofile` は作らない）。同じ行が既に `lib/zshrc` にある（今回足したものを含む）なら、その行は足さない。
  - 足したら `zsh -n lib/zshrc` で構文を確かめる。
- **ローカルから消す**: 共通化した zsh の段落（`in-dotfiles` を含む）を `~/.zshrc` / `~/.zprofile` から消す。ファイルごとにまとめて行う。
  1. 段落を除いた内容を一時ファイル（`mktemp`）に作る。dotfiles ブロック（`# >>> dotfiles` から `# <<< dotfiles` まで）と `brew shellenv` の行は残す。
  2. `diff -u <ファイル> <一時ファイル>` を見せ、AskUserQuestion で消すかを確認する。
  3. 消すなら `cp -p <ファイル> <ファイル>.backup-$(date +%Y%m%d%H%M%S)` で退避してから、`cat <一時ファイル> > <ファイル>` で書き換える。退避先を伝える。
- **破棄（lib）**: `id` の `lib:` の後ろのパスを、追跡しているファイルなら `git restore <パス>`、未追跡なら削除する。`lib/com.googlecode.iterm2.plist` を破棄するときは、iTerm2 が起動中だと終了時に設定が書き戻されることを伝える。
- **ローカル専用**: 除外リスト `${DOTFILES_IGNORE_FILE:-$HOME/.config/dotfiles/ignore}` の末尾に `id` を 1 行で足す。ディレクトリが無ければ作る。`id` には `$` や引用符が入るので、`cat >> <ファイル> <<'EOF'` のように展開しない形で書く。
- **commit（lib）**: 4 で commit する。
- **保留**、**残す**: 何もしない（次回また出る）。

すべての選択を反映したら、次に進む。

### 4. commit

リポジトリに変更が無ければ、4 と 5 は飛ばす。

1. `git status --short` と `git diff` を見せる。未追跡のファイルは中身を見せる。plist は生の diff が長いので、`git diff --stat` と collect の要約を見せ、全文は聞かれたら見せる。AskUserQuestion で commit するかを確認する。
2. エリアごとに 1 commit にする（Brewfile、zsh、`lib/` の変更はファイルごと）。そのエリアのファイルだけを `git add <パス>` で入れ、`main` に直接 commit する。
3. メッセージは `[feat]` `[fix]` `[del]` + 日本語の要約。例: `[feat] Brewfile に actionlint などを追加`、`[feat] zshrc に rbenv の初期化を追加`、`[del] Brewfile から gitkraken を削除`、`[feat] iTerm2 の設定を更新`。

commit したら `collect --no-fetch` を実行し直し、残っている項目が、保留・残すにしたものと、ローカルから消すのを断った段落だけであることを確かめる。

### 5. push

ツールの追加を頼まれていれば、先に「ツールの追加」を行う。

AskUserQuestion で `origin main` に push するかを聞く。おすすめは「push する」。push するなら `git push origin main`。拒否されたら（origin が先に進んでいるなど）、そのことを伝えて止める。

## ツールの追加

起動時の引数か会話でツールを管理に加えるよう頼まれたときだけ行う。差分の確認（流れの 1〜4）が済んでから行い、push は流れの 5 で最後に 1 回だけ聞く。

1. **反映方法を提案する**: ツールの設定ファイルの場所を調べ、方法を提案して AskUserQuestion で確認する。
   - 原則はシンボリックリンク: 設定を `lib/<tool>/` に移し、元の場所をそこへのリンクにする（starship と同じ）。以後のローカルの変更は、`lib` の未コミットの変更として流れの 2 に出てくる。
   - Mac ごとの値や秘密情報が混ざるファイルは、ツールの include 機能を使う（例: git は `~/.gitconfig` に `[include] path = <リポジトリ>/lib/gitconfig`）。共通の部分だけを `lib/` に置き、ローカルのファイルに残りを残す。
   - ツールが設定を書き換えるときに、リンクを保つか（普通のファイルに置き換えないか）を、ドキュメントや既知の issue で確かめる。保たないなら include など別の方式にする。
2. **README の「ツールを追加する」の手順で足す**:
   - 設定ファイルを `lib/` にコピーする。「おすすめの決め方」の `secret` や `garbage` に当たる行は除く。元のファイルは、次の手順の `cmd/setup` が退避してリンクに置き換える。
   - `cmd/setup` に冪等な `setup_<tool>` を足し、末尾の手順の並びに `step` と呼び出しを足す（`setup_starship` のように `cmd/common.sh` の `is_linked` / `link_file` を使う）。
   - `lib/<tool>.md` を書き、README の表に 1 行足す。
3. **collect に検出を足す**: include 方式のように `lib` の変更として出てこないものは、そのツールの差分を集める処理を `collect` に足し、ほかの項目と同じ `=== item` の形式で出す（`kind` は新しい名前、`id` は `<kind>:<識別子>`）。`shellcheck` を通す。VS Code を加えるときは、Brewfile の `vscode` 行（拡張機能）の検出もここで足す。
4. **setup を実行してもらう**: ユーザーにこのセッションで `! <リポジトリの絶対パス>/cmd/setup` を実行してもらう（質問に答えられなければ、別のターミナルで実行してもらう）。ローカルのファイルがリンク（または include）に切り替わったことを `ls -l` などで確かめる。
5. **commit**: 流れの 4 と同じやり方で、ツールごとに 1 commit にする（例: `[feat] VS Code の設定を管理に加える`）。その後、流れの 5 に戻って push するかを聞く。
