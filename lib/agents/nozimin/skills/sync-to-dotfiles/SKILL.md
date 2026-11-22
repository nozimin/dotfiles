---
name: sync-to-dotfiles
description: この Mac の設定と dotfiles の差分を表で見せ、選んだものを dotfiles に取り込む。引数で伝えたツールを管理に加える。
argument-hint: "[追加したいツール]"
disable-model-invocation: true
---

# sync-to-dotfiles

この Mac の Homebrew のパッケージ、`~/.zshrc` / `~/.zprofile`、`lib/` の未コミットの変更を dotfiles と比べ、ユーザーが選んだものを dotfiles に取り込む。`cmd/setup`（dotfiles → この Mac）の逆向き。

- 扱うのは `collect` が出す差分だけ。新しいツールを管理に加えるのは、起動時の引数か会話でユーザーが頼んだときだけ（「ツールの追加」）。
- commit は `main` に直接行う。個人用の dotfiles なので、ブランチも PR も作らない（ユーザーが決めたこと）。
- dotfiles のファイル操作や Git 操作は `~/.config/dotfiles/repo` のパスで行う。
- 最初の `collect` が出す `=== repo` の `path` を `repo_path` として記録し、この実行で使い続ける。後続の `collect` には毎回 `--expect-repo "$repo_path"` を付ける。リポジトリやローカル設定を書き換える操作は、必ず `"$lock_script" "$repo_path" -- <command>` で実行する。この helper は実行直前に pointer と移行 marker を再検証し、installer の lock を保持して command を実行する。確認後に pointer が変わった、marker がある、または lock が取れない場合は何も書かずに止め、pointer を読み直して選択を続けず、collect と承認からやり直す。
- この skill に同梱したスクリプトは `scripts/` にある。skill loader が示すこの `SKILL.md` の絶対パスから `skill_scripts`（同じディレクトリの `scripts/` の絶対パス）を求め、すべてのコマンドでその絶対パスを使う。helper は repo root へ `cd` してから command を起動するため、相対パスを渡さない。各 shell 呼び出しで `lock_script="$skill_scripts/with-repo-lock"` と `collect_script="$skill_scripts/collect"` を設定する。別々の Bash 呼び出しで変数が引き継がれない場合も、読み込まれた `SKILL.md` の絶対パスから作り直す。

## collect の出力

`"$collect_script"` は差分を標準出力に出す。読み取り専用で、書き込むのは `git fetch` だけ。`--no-fetch` を付けると fetch しない（fetch は 30 秒で打ち切る。ssh の origin では `BatchMode` と `ConnectTimeout` を付けるが、`GIT_SSH_COMMAND` `GIT_SSH` `core.sshCommand` をユーザーが決めていればそれを使う）。終了コード 1 は、出力できなかったことを表す。別の操作（本文の取り出し、作業ツリーとの比較、範囲の確認と削除）は、サブモード（下の「collect のサブモード」）で行う。

dotfiles 側は `HEAD` の `lib/Brewfile` と `lib/zshrc` と比べる。作業ツリーの未コミットの変更は `lib` の項目として別に出るので、未コミットの変更にしかない行は「dotfiles にある」にならない（`in-dotfiles` が立たず、Brewfile の項目も出る）。

出力は `=== <名前>` で始まるブロックの並び:

- `=== repo`: `branch`（detached HEAD なら `HEAD`）、`behind` / `ahead`（`origin/<branch>` との差のコミット数。`--no-fetch` ならローカルの追跡ブランチで数える。fetch の失敗、`origin/<branch>` が無い、detached HEAD のときは `unknown` で、理由が `=== warn` に出る）、`dirty`（`lib/` 以外の未コミットの変更。未追跡を含む。1 ファイル 1 行。無ければ行が無い）、`zshrc-block`（`~/.zshrc` の dotfiles ブロックの行の範囲。`7-9` の形。無ければ `none`。閉じていないブロックはファイルの最後まで）、`zshrc-sources-lib`（そのブロックの中に、このリポジトリの `lib/zshrc` を `source` か `.` で読み込む行があるか。`yes` / `no`）。`zshrc-block` と `zshrc-sources-lib` は、4 の commit の後で段落をローカルから消してよいかと、消すと実行順が変わるかを決めるのに使う（「ローカルから消す」）。
  - dotfiles ブロックは、`cmd/common.sh` の `has_block` と同じく、`# >>> dotfiles >>>`（`cmd/setup`）か `# >>> dotfiles: <名前> >>>`（`cmd/install_brew` の `# >>> dotfiles: homebrew >>>` など）を含む行から、同じ名前の `# <<< ... <<<` を含む行まで。`# >>> dotfiles-work >>>` など、名前が違うものはブロックではない（段落として項目に出る）。閉じていないブロックはファイルの最後まで。
  - ブロックが複数あるときは、このリポジトリの `lib/zshrc` を読み込む行があるブロックが `zshrc-block` になる。どのブロックにも無ければ最初のブロックで、`zshrc-sources-lib` は `no`。
  - 同じリポジトリの別の worktree の `lib/zshrc` を読み込んでいても `yes`（worktree で collect を実行しても、`~/.zshrc` は元の場所の `lib/zshrc` を読み込んでいるため）。別の clone の `lib/zshrc`、コメントアウトした行、`~/` `$HOME/` `${HOME}/` のほかの変数で書いたパスは `no` になる。
- `=== item`: 差分 1 件。
  - `kind`: `brew` `cask` `tap`（Brewfile）、`zshrc` `zprofile`（dotfiles ブロックの外を、空行か空白だけの行で区切った段落。100 文字以上の空白だけの行は区切りにならず、段落に残って `garbage` になる）、`lib`（`lib/` の未コミットの変更）。
    - `brew` `cask`: 名前の最後の `/` より後ろで比べる。Brewfile の名前が別名や古い名前（`postgresql` → `postgresql@14` など）なら、`brew info` の `aliases` / `oldnames`（cask は `old_tokens`）でインストール済みの名前に読み替えてから比べるので、項目にならない（`brew info` を読むのは、Brewfile にインストールされていない名前があるときだけ）。`jq` が無いか `brew info` を読めないと読み替えず、`=== warn` に出る（このときは、同じものが逆向きの差分とローカルの項目の 2 件に分かれて出ることがある。「おすすめの決め方」）。brew は `PATH` に無ければ `cmd/common.sh` の `load_brew` で探される。
    - `tap`: `homebrew/core` と `homebrew/cask` は出ない。Brewfile の完全な名前の行（`brew "user/tap/foo"`）から暗黙に追加される tap は、Brewfile にあるものとして扱われる（`tap "..."` の行が無くても、ローカルにあれば出ない）。逆向きの差分（`direction: dotfiles`）に出るのは `tap "..."` の行があるものだけ（暗黙に追加される tap には、消せる行が無いため）。
    - `zprofile`: コードの部分（行末のコメントを除いた部分）に `brew shellenv` を含む段落は、段落ごと出ない（dotfiles ブロックを入れる前に追記されたもの。arm64 と Intel で分ける `if` / `else` の一部だけを消すと、残った `eval` が無条件に走るため）。段落をつなぐか（下）は元の内容で決まり、除くのはつないだ後（`foo &&`、空行、`eval "$(brew shellenv)"` は、つないだ 1 段落ごと出ない）。同じ段落にほかの設定があっても項目にならないので、除いた段落の行の範囲が `=== warn` に出る。行末のコメントにだけ `brew shellenv` がある行（`export PATH=... # brew shellenv の前に`）は除かれない。
    - `zshrc` `zprofile` の段落は、`if` や関数の途中で切れないよう、`zsh -n` が通るまで次の段落とつないである。閉じていないヒアドキュメント（`cat <<EOF` の終わりの行がまだ無い）と、最後のコメントでない行の、行末のコメントを除いたコードの部分が `\` `&&` `||` `|` で終わる段落も、`zsh -n` は通るが完結していないので、次の段落とつないである（`foo &&`、空行、`bar` は 1 項目。`foo && # note`、空行、`bar` も 1 項目）。`\\`（エスケープした `\`）で終わる行と、コメントの行（`# a ||`）は続きにならない。dotfiles ブロックを越えてはつながない。ファイルの最後か dotfiles ブロックの手前までつないでも通らなければ、そこまでが 1 項目になり、`=== warn` に出る。閉じない段落が続くと、つなぐたびに `zsh -n` をかけ直すので、collect に時間がかかることがある（`<<` を含まなければ `zsh -n` は 1 回、含めば 2 回）。
  - `id`: 除外リストに書く識別子。`id: ` の後ろの全体で、`<kind>:<識別子>` の形。
    - `brew` `cask` `tap`: `<kind>:<名前>`。名前は `body` と同じ。
    - `zshrc` `zprofile`: `<kind>:<つないだ行>`。つないだ行は、段落のコメントでない行を前後の空白を除き、` ⏎ `（前後に空白）でつないだもの（1 行の段落ならその行）。段落の中身が変わると、別の項目になる。
    - `secret` が立つ `zshrc` `zprofile`: `<kind>:sha256:<つないだ行の SHA-256>`（末尾に改行を付けずに求めた 64 桁の 16 進数）。秘密情報は `id` に入らない。
    - `lib`: `lib:<リポジトリからの相対パス>`。
  - `lines`: `zshrc` `zprofile` だけ（`id` の次の行）。段落がファイルの何行目から何行目か（`lines: 12-15`。1 から数える）。ファイルの中の段落の場所は、`id` や `body` の文字列で探さず、これで決める（同じ内容の段落が 2 つあっても取り違えないため）。範囲の行は、`body` の行と 1 行ずつ対応する。
  - `direction`: `local`（ローカルにだけある）、`dotfiles`（`HEAD` の Brewfile にあるのに未インストール）、`changed`（`lib/` の変更）。
  - `flags`: カンマ区切り（並びは優先順ではない）。無ければ `-`。`brew` `cask` `tap` には付かない。`lib` は足された内容（diff の `+` 行、未追跡のファイル全体、plist の変更後の値）だけで、全文について判定され（`body` を 200 行で切る前の内容。201 行目より後の秘密情報も見る）、`in-dotfiles` は付かない。バイナリなど中身を調べられなかったものには `unscanned` が付く。意味は「おすすめの決め方」。
  - `body:` の後の行: 本文。各行の先頭の 4 スペースを外すと元の行になる。ただし `secret` が立つ項目は、秘密と判定した値が `***` に置き換わっていて、元の値は出ない（`id` の SHA-256 と `flags` は置き換える前の内容から求めてある）。`lib` の diff では、足された行だけでなく、消された行と前後の文脈の行も同じ条件で置き換わる（`flags` は足された行だけで判定される。秘密を消す変更は `secret` が立たずに commit を選べるが、`body` では消される秘密の値も `***` になる）。plist の変更前の値も同じ。
    - `brew` `cask` `tap`: 名前。サードパーティの tap のものは `<user>/<tap>/<名前>` の完全な名前（`id` も同じ）、`homebrew/core` と `homebrew/cask` のものは短い名前。
    - `zshrc` `zprofile`: 段落の全文（コメントの行を含む）。つないだ段落は間の空行も含み、空行は 4 スペースだけの行になる。
    - `lib`: 変更の要約。plist は変わったキーのパスと前後の値（80 文字を超える値は省略）で、`Guid` を持つ配列の要素は `[Guid=<値>]` で表す（同じ配列で `Guid` が重なる要素は位置）。それ以外と plist として読めないものは `git diff`。200 行を超える要約は省略され、末尾にそう書かれる。
  - `lib` の `body` の先頭には、状態を表す括弧書きの補助の行が付くことがある: `(未追跡のファイル)`（続けて中身の先頭 200 行）、`(シンボリックリンク: <リンク先>)`、`(空のファイル)`、`(バイナリファイル)`、`(HEAD との差分はありません)` など。補助の行はファイルの中身ではない。
- `=== warn`: 確認できなかったこと。1 行 1 件。無ければブロックが無い。例:
  - `brew が見つからないため、brew / cask / tap を確認していません`
  - `~/.zprofile の dotfiles ブロックが閉じていないため、ブロックの開始行より後ろを確認していません`
  - `~/.zshrc の 14 行目からの段落は、ファイルの最後か dotfiles ブロックの手前までつないでも構文として完結しない（zsh -n が通らないか、ヒアドキュメントが閉じていないか、最後の行が \ && || | で終わる）ため、そこまでを 1 項目にしています`（行番号は、その項目の `lines` の開始行。この項目は構文が完結していない。項目にならなかった段落（`brew shellenv` を含むものなど）には、この warn は出ない）
  - `~/.config/dotfiles/ignore の lib:lib/zshrc は、lib の項目はローカル専用にできないため無視しています`
  - `~/.zprofile の 2-2 行目は brew shellenv を含む段落のため、項目にしていません（同じ段落のほかの設定も出していません）`（行の範囲は、つないだ後の段落全体）。その範囲にほかの設定があっても項目に出ないことを伝える（ユーザーが空行で `brew shellenv` の段落と分ければ、次から項目に出る。エージェントはファイルを書き換えない）。
  - `jq が見つからないため、Brewfile の別名や古い名前（postgresql → postgresql@14 など）を読み替えていません`、`brew info --json=v2 --installed を読めなかったため、Brewfile の別名や古い名前（postgresql → postgresql@14 など）を読み替えていません`（「おすすめの決め方」の、2 件に分かれて出る項目の扱い）。
- `=== summary`: `items`（項目数）と `ignored`（除外リストで除いた数）。除外リストの行は、行末の空白と CR を除いてから `id` と比べられる。除外されるのは `direction: local` の項目だけで、逆向きの差分は同じ `id` が除外リストにあっても出る（除外リストはローカル専用から作られるため）。`lib:` で始まる行は無視され、`=== warn` に出る（`lib` の項目はローカル専用にできない。隠すと、その未コミットの変更が取り込みの commit に混ざるため）。

## collect のサブモード

どれも読み取り専用で、結果は標準出力だけに出す（ファイルは書き換えない）。ファイルの中身（秘密を含みうる）を画面に出さない形にしてあるので、下の手順では、`cat` `sed` `awk` で自分で切り出さずにこれらを使う。`<出力ファイル>` は 1 で残した collect の出力、`kind` と `lines` は項目のもの（`lines: 12-15` なら `12-15`）。終了コード 1 は、項目が見つからないか、一致しなかったこと。引数の誤りは終了コード 1 でメッセージが出る。

| 呼び出し | 出力 |
|---|---|
| `collect --expect-repo "$repo_path" --body <出力ファイル> <kind> <lines>` | その項目の `body`（先頭の 4 スペースを外したもの）。1 で見た本文なので画面に出してよいが、長ければファイルにリダイレクトする |
| `collect --expect-repo "$repo_path" --in-worktree <出力ファイル> <kind> <lines>` | その段落が作業ツリーの `lib/zshrc` にあるか。`yes` か `no`。`in-dotfiles` と同じ比べ方（下の「段落の確かめ方」）で、`HEAD` の代わりに作業ツリー |
| `collect --expect-repo "$repo_path" --check <出力ファイル> <kind> <ファイル> <lines>...` | ファイルの各範囲の内容が、その項目の `body` と一致するか。範囲ごとに `<lines>: 一致` か `<lines>: 不一致`。中身は出ない。1 つでも不一致なら終了コード 1 |
| `collect --expect-repo "$repo_path" --between <ファイル> <from> <to か end> [skip...]` | ファイルの `from` 行目から `to` 行目（`end` なら最後）までのうち、`skip`（`12-13` の形の範囲を空白区切りで並べる）に入らないコードの行（空行と `#` で始まる行以外）の行番号。中身は出ない |
| `collect --expect-repo "$repo_path" --without <ファイル> <lines>...` | ファイルから各範囲の行を除いた内容。**必ず一時ファイルにリダイレクトする**（`> "$tmp"`。端末に出そうとするとエラーになる）。範囲は順不同でまとめて渡せる。元のファイルは書き換えない |
| `collect --expect-repo "$repo_path" --diff <パス>...` | `lib/` のファイルの `HEAD` との差分（未追跡のファイルは中身）。秘密と判定した値は、消された行と文脈の行を含めて `***`。plist は変更の要約。行数は切らない |

## 流れ

### 1. 開始時の確認

`~/.config/dotfiles/repo` から `repo_path` を読み、出力は一時ファイルに残す（4 の commit の後で段落を消すときに、サブモードがこのファイルから `body` を取り出して照らし合わせるため）。最初の読み取りと `collect` は helper の lock 内で行い、`collect --expect-repo` が pointer と clone の一致を検証する。出力に表示された `path` をこの実行の承認対象として記録する。終了コード 1 なら、エラーを伝えて止める。

```sh
# Replace this value with the absolute SKILL.md path supplied by the skill loader.
skill_file="<absolute path to this loaded SKILL.md>"
skill_scripts="$(cd "$(dirname "$skill_file")/scripts" && pwd -P)" || exit 1
lock_script="$skill_scripts/with-repo-lock"
collect_script="$skill_scripts/collect"
repo_path="$(cat "$HOME/.config/dotfiles/repo")"
out="$(mktemp)"
if ! "$lock_script" "$repo_path" -- "$collect_script" --expect-repo "$repo_path" > "$out"; then echo "collect に失敗しました: $out"; exit 1; fi
echo "出力: $out repo: $repo_path"
cat "$out"
```

`=== repo` を見る:

- `branch` が `main` でなければ止め、`main` で起動し直すよう伝える。
- `dirty` があれば止め、そのファイルを伝える（commit か破棄をしてから起動し直す）。
- `behind` が 1 以上なら、AskUserQuestion で `git pull --ff-only` するかを聞く。おすすめは「pull する」。
  - pull は `"$lock_script" "$repo_path" -- git -C "$repo_path" pull --ff-only` で実行する。pull したら `"$collect_script" --expect-repo "$repo_path" --no-fetch` を実行し直し、その出力で続ける（出力は同じように一時ファイルに残し、以後はそのファイルを使う）。
  - pull が失敗したら（ローカルと origin が分岐しているなど）、止めて伝える。
  - pull しないなら、最後の push が拒否されうることを伝えて続ける。
- `behind` が `unknown` なら、origin と比べられなかったことを伝え、AskUserQuestion で続けるかを聞く。
- `ahead` が 1 以上なら、push していない commit があり、最後の push に含まれることを伝える。

`branch` が `main` で `dirty` が無く、pull の判断まで済んだ `collect` の出力が手元にあれば、次に進む。

### 2. 表で選んでもらう

先に `=== warn` の内容と、除外リストで除いた数（`ignored`）を伝える。項目が 0 件なら、差分が無いことを伝え、3 と 4 を飛ばして 5 に進む（ツールの追加を頼まれていればそれを行う。push するものが無ければそのまま終わる）。

項目をエリアごとの表にする。番号はエリアをまたいで通し番号にする。

| エリア | 項目 | 選択肢 |
|---|---|---|
| Brewfile | `brew` `cask` `tap` で `direction: local` | 共通化／ローカル専用／保留 |
| zsh | `zshrc` `zprofile` | 共通化／ローカル専用／保留。`secret` があればローカル専用／保留だけ |
| `lib/` の変更 | `lib` | commit／破棄（`git restore`）／保留。`secret` があれば破棄／保留だけ。`unscanned` があれば、おすすめは保留 |
| 逆向きの差分 | `direction: dotfiles` | 残す（デフォルト）／dotfiles から削除 |

取り込み先のファイル（`lib/Brewfile`、`lib/zshrc`）の `lib` の項目も、表ではほかの `lib` の項目と同じく保留を選べる。この回にそのファイルへの取り込みもあるときは、選択が決まった後に選び直してもらう（下の「取り込み先のファイルの保留」）。

表の書き方:

- 表の列は「#、項目、おすすめ、理由」。フラグがあれば理由に書く。
- zsh の項目には、ファイルと `lines` の行番号を書く（同じ段落が 2 つあっても区別できるように）。
- 同じ設定の段落が複数ある（`~/.zshrc` と `~/.zprofile` の `rbenv init` など。`lib/zshrc` に既にあるものを含む）ときは、`lib/zshrc` には 1 つにまとめて足す。どの段落を残すかを理由に書く（例: 「#4 と同じ設定。#4 の段落を足し、#4 と #5 をローカルから消す」）。
- `~/.zprofile` の段落があれば、表の下に「`~/.zprofile` の段落も `lib/zshrc` に入れる。`lib/zshrc` は対話シェルでしか読まれないので、`zsh -l -c` のような非対話のログインシェルでは効かなくなる」と書く。ユーザーが受け入れたことなので、おすすめは変えない。
- zsh の項目があり、`zshrc-sources-lib` が `yes` でなければ、表の下に「`~/.zshrc` が `lib/zshrc` を読み込んでいないので、共通化した段落もこの回はローカルから消さない。読み込むには別のターミナルで `cmd/setup` を実行する」と書く（「ローカルから消す」の「読み込み」）。
- zsh と `lib/` の項目は、表の下に番号ごとの本文をコードブロックで見せる。長い `lib` の要約は抜粋し、残りは聞かれたら見せる。
- 表と本文に載せるのは collect の `body` だけにする。`secret` の項目は、秘密の値が `***` に置き換わった `body` をそのまま見せる。秘密の値を `~/.zshrc` などのローカルのファイルや `git diff` から読み出して見せない（チャットと transcript に残るため。Bash の出力も残る）。値を確かめたいと言われたら、ユーザー自身にエディタで開いてもらう。
- 最後に「変えたい番号と選択肢だけ答えてください（例: `3 保留, 7 ローカル専用`）。すべておすすめどおりなら OK」と書き、ターンを終えて返事を待つ。

```markdown
**Brewfile**

| # | 項目 | おすすめ | 理由 |
|---|---|---|---|
| 1 | brew `actionlint` | 共通化 | GitHub Actions の lint。どの Mac でも使う |
| 2 | brew `rbenv` | 共通化 | Ruby のバージョン管理。#4 と揃える |

**zsh**

| # | 項目 | おすすめ | 理由 |
|---|---|---|---|
| 3 | `~/.zshrc` 12 行目の `alias gcomi=...` | ローカル専用 | `missing-path`: `~/Script/cmd/commit` が無い |
| 4 | `~/.zshrc` 20-21 行目の `eval "$(rbenv init - zsh)"` | 共通化 | #2 と揃える |
| 5 | `~/.zprofile` 3-4 行目の `eval "$(rbenv init - zsh)"` | 共通化 | #4 と同じ設定。#4 の段落を足し、#4 と #5 をローカルから消す |
```

選べない選択肢（`secret` の項目の共通化と commit）を選ばれたら、理由を伝え、選べる選択肢から選び直してもらう。

#### 取り込み先のファイルの保留

選択が決まったら、`lib/Brewfile` と `lib/zshrc` について、次の 2 つが両方あるかを確かめる。あると、保留の変更が 4 の取り込みの commit に混ざる。

- そのファイルの `lib` の項目が保留。
- そのファイルへの取り込み。`lib/Brewfile` なら Brewfile の共通化か「dotfiles から削除」、`lib/zshrc` なら `lib/zshrc` に段落を足す zsh の共通化（`in-dotfiles` の段落だけなら、ローカルから消すだけなので当たらない）。保留にする未コミットの変更にだけある段落や行（`HEAD` には無いので `in-dotfiles` が立たず、Brewfile の項目にも出る）の共通化も当たる。

両方あれば、ファイルごとに AskUserQuestion で次のどれにするかを聞く。おすすめは「取り込みも保留」（何も失われず、次回また出る）。

- その `lib` の項目を commit にする（取り込みと同じ commit になる）。`secret` があれば選べない。
- その `lib` の項目を破棄にする（変更が消え、戻せない）。
- そのファイルへの取り込みも、この回は保留にする（そのファイルに足す・消す項目と、それと 1 つにまとめた段落をすべて保留にする）。

取り込みが無ければ、保留のままでよい。

すべての項目の選択が決まったら、次に進む。

#### おすすめの決め方

zsh の項目はフラグで決める。フラグが複数あれば、表の上にあるものを優先する。

| フラグ | 意味 | おすすめ |
|---|---|---|
| `secret` | トークンらしい文字列がある（下の条件）。`body` では秘密の値が `***` になっている | ローカル専用（共通化は選べない。ローカル専用か保留だけ） |
| `unscanned` | `lib` だけ。中身を調べられていない（バイナリ、plist の `data:` の値で base64 として読めないもの）。plist の `data:` は base64 を戻して、見える文字の並びを `secret` の条件で調べる（調べられたものには付かない。圧縮や暗号化された中身は調べられない） | commit をおすすめしない（保留。理由に「中身を確かめていない」と書く）。commit も選べる |
| `in-dotfiles` | 段落のコメントでない行の並びが、`HEAD` の `lib/zshrc` のコメントでない行の中に、同じ順で連続して現れ、その位置が `lib/zshrc` のトップレベル（`if` や関数、ヒアドキュメントの中でない）にある（前後の空白を除いて比べる。トップレベルは、その行より前までと、一致した行が、それぞれ `zsh -n` で完結することで決める。`lib/zshrc` の `if ...; then` の中の字下げした同じ行は当たらない。一部の行を抜いた変形版、並びの違うもの、未コミットの変更にしかない行でも立たない） | 共通化（dotfiles にあるので、ローカルから消すだけ） |
| `missing-path` | コードの部分（コメントの行と行末のコメントを除く）で、存在しないパス（`~/...` `$HOME/...` `${HOME}/...` `/Users/...`。引用符で囲んだパスと `\ ` でエスケープした空白は、パスの一部として見る）を参照している | ローカル専用 |
| `home-path` | コードの部分（コメントの行と行末のコメントを除く）に `/Users/<ユーザー名>/...` を含む | 共通化。取り込むときに `$HOME` か `~` に書き換える |
| `garbage` | 1000 文字以上の行か、100 文字以上の空白だけの行がある | ほかの条件で決め、取り込むときにその行を消す |

`secret` が立つのは次のどれかがあるとき:

- 秘密らしい名前（`TOKEN` `SECRET` `PASSWORD` `PASSWD` `API_KEY` `APIKEY` `PRIVATE_KEY` `CREDENTIAL` を含むか、`_KEY` で終わる。大文字小文字は区別しない）の変数への代入。行の中の `NAME=値` の形の単語を見る（`export` `sudo` `env` の引数、`;` `{` `then` `if` の後なども含む。`alias` の名前と `[[ ... ]]` の中は代入ではない）。`alias` の値（引用符の中）は、その中をコマンドとして同じ条件で見る（`alias deploy='HEROKU_API_KEY=... heroku deploy'` は立つ）。
- 設定ファイル形式の `キー: 値`、`キー = 値`、`"キー": "値"` で、キーが秘密らしい名前のもの。`#` `;` で始まる行はコメントとして見ないが、`//` で始まる行（`.npmrc` の `//registry.npmjs.org/:_authToken=...`）は見る。`{` か `[` で始まる値と、`""` で囲んだキーに `""` で囲んでいない値が付くもの（JSON の `null` など）は見ない。
- 上の 2 つでは、値が `$` で始まるもの、空、パス（`~` `/` `./` `../` で始まるもの、名前が `_FILE` `_PATH` `_DIR` で終わるもの、`.txt` `.json` `.yaml` `.yml` `.toml` `.pem` `.key` `.conf` `.cfg` `.ini` `.env` `.gpg` `.asc` で終わるもの。`SSH_KEY=~/.ssh/id_rsa`、`TOKEN_DIR=./tokens`、`API_KEY_PATH=keys/api`、`TOKEN_FILE=token.txt`、`GPG_KEY=signing.asc` など）、真偽値や数値だけのもの（`TOKENIZERS_PARALLELISM=false`、`MAX_TOKENS=4096` など）は除く。ただし名前が `PASSWORD` `PASSWD` `SECRET` `PIN` で終われば数値だけでも立ち（`PASSWORD=12345`。`PASSWORD_STORE_CLIP_TIME=45` は終わりが違うので立たない）、単一引用符で囲んだ値と `$'...'` は `$` で始まっても立つ（`'$abc123'` と `$'abc123def'` は展開されない文字列）。`/` を含むだけの値はパスとみなさないので立つ（`AWS_SECRET_ACCESS_KEY=wJalr.../K7MD...` のような base64 の秘密は `/` を含む。`OAUTH_TOKEN_URL=https://...` のような URL も立つ）。
- `ghp_` `gho_` `github_pat_` `npm_` `glpat-` `AIza` `sk-` `sk_live_` `rk_live_` `xox?-` `AKIA` で始まる値、`Bearer <トークン>`（16 文字以上）、`_authToken=<値>`（8 文字以上）、`-----BEGIN ... PRIVATE KEY-----`。接頭辞は、行頭か、英数字と `_` 以外の文字の直後から始まり、ある程度の長さが続くものだけ（`${GH_TOKEN:-ghp_...}` の `-` の後は立つ。`disk-` などでは立たない）。`Bearer` と `_authToken` は、`$` で始まる値（`.npmrc` の `_authToken=${NPM_TOKEN}` など）では立たない。
- URL の中の認証情報（`://<ユーザー>:<パスワード>@`）で、パスワードが `$` で始まらないもの。

`lib` の項目は、`secret` があれば commit を選べない（破棄か保留だけ）。おすすめは保留。`unscanned` があれば、commit は選べるが、おすすめは保留にする（中身を確かめていないものを commit すると、秘密情報が入りうるため）。ほかのフラグ（`home-path` `missing-path` `garbage`）は理由に書くだけで、おすすめはフラグが無いときと同じく内容から決める。commit するときもファイルは書き換えない。`secret` は足された行だけで判定するので、秘密情報を消す変更には立たない（commit を選べる。`body` では、消される行の値も `***` になっている）。

`secret` は書き方の形で判定するので、plist のキーの名前（値が `ghp_` などで始まるときだけ立つ）や、ハイフンを含むキー名（`api-key: ...`。既知の制限）では立たない。フラグが無くても本文に秘密らしい値が見えたら、共通化や commit をおすすめせず、理由に書く。この場合 `body` の値は `***` になっていないので、表の下で本文を見せるときはその値を `***` に置き換える。

フラグが無い項目は内容から決める:

- どの Mac でも使う開発ツールや設定は共通化。特定の案件やこの Mac の事情によるものはローカル専用。判断がつかなければ保留。
- 関連する項目（`rbenv` の brew と `rbenv init` の段落など）は、おすすめを揃える。
- `tap` は、その tap の formula や cask の項目に揃える。その tap のものを何も共通化しないなら、`tap` だけ足しても何も入らないので、ローカル専用か保留。
- `jq` が無いか `brew info` を読めない（`=== warn` に出る）と Brewfile の別名を読み替えないので、同じものが逆向きの差分（Brewfile の `brew "postgresql"`）とローカルの項目（インストール済みの `postgresql@14`）に分かれて出ることがある。名前から同じものらしければ、逆向きは「残す」、ローカルの項目は「保留」にし、理由に書く（例: 「#12 の別名かもしれない。jq が無く読み替えていない」。共通化すると Brewfile に同じものが 2 行入る）。
- `lib/Brewfile` や `lib/zshrc` の未コミットの変更（`lib` の項目）に既にある行や段落も、`HEAD` に無ければ Brewfile と zsh の項目に出る。その `lib` の項目を commit するなら、3 では足さない（zsh の段落はローカルから消すだけになる）。理由にそう書く（例: 「#9 の `lib/zshrc` の変更に同じ段落がある。#9 を commit すれば足さない」）。
- `lib` は、意図した設定の変更なら commit。判断がつかなければ保留（取り込み先のファイルも同じ。取り込みと重なったら「取り込み先のファイルの保留」で聞く）。
- 逆向きの差分は「残す」。

### 3. 反映

選択ごとに、次の順に行う。

書き込み前に、元の `repo_path` を必ず `"$lock_script" "$repo_path" -- <command>` に渡す。repo 内の編集、`git restore` / `rm` / `git add` / `git commit` / `git pull` / `git push`、`~/.config/dotfiles/ignore` への追記、`~/.zshrc` / `~/.zprofile` のバックアップと置き換えはすべて対象。ファイル編集ツールから直接 repo を書かず、patch や一時出力を作って helper の中で適用する。複数行の処理は helper 経由の `bash -s` に heredoc を渡す。helper が pointer 変更や移行を検出して失敗したら、そのコマンドは実行されていない。選択を引き継がず、collect からやり直す。

1. `lib` の破棄
2. Brewfile と zsh の取り込み（共通化、dotfiles から削除）
3. 除外リストへの追記（ローカル専用）

`lib` の破棄を最初に行うのは、後から破棄すると、取り込みで足した内容まで `git restore` で消えるため（ローカル側も消すと、設定がどこにも残らなくなる）。共通化した zsh の段落をローカルから消すのは、ここではなく 4 の commit の後にする（「ローカルから消す」）。

リポジトリで変えたファイル（取り込み先と dotfiles から削除したファイル、commit を選んだ `lib` の項目のパス）を、エリアごとに覚えておく。4 で commit するのはこのファイルだけ。

- **破棄（lib）**: `id` の `lib:` の後ろのパスを、`body` の先頭が `(未追跡のファイル)` なら `"$lock_script" "$repo_path" -- rm -- "$repo_path/<パス>"` で削除し、それ以外なら `"$lock_script" "$repo_path" -- git -C "$repo_path" restore --source=HEAD --staged --worktree -- <パス>` で `HEAD` に戻す。`lib/com.googlecode.iterm2.plist` を破棄するときは、iTerm2 が起動中だと終了時に設定が書き戻されることを伝える。
- **共通化（Brewfile）**: `lib/Brewfile` の合うセクションの末尾に `brew "<名前>"` / `cask "<名前>"` / `tap "<名前>"` を足す。名前は `body` のまま書く（サードパーティの tap のものは完全な名前で出るので、短くしない。短い名前だと新しい Mac の `brew bundle` が失敗する）。formula は `# CLI`、アプリの cask は `# アプリ`、フォントの cask は `# フォント`。合うセクションが無ければ（`tap` など）コメント付きのセクションを足す。`tap` のセクションは先頭に置く。作業ツリーの `lib/Brewfile` に同じ名前の行が既にあれば（この回に commit する未コミットの変更で足してある）、足さない（二重に入るため）。
- **dotfiles から削除**: `lib/Brewfile` からその行を消す。作業ツリーに行が無ければ（未コミットの変更で消してある）、何もしない。
- **共通化（zsh）**: 段落を `lib/zshrc` に足す。
  - 作業ツリーの `lib/zshrc` にその段落が既にあれば（下の「段落の確かめ方」の `collect --in-worktree` が `yes`。この回に commit する未コミットの変更で足してある）、足さない（二重に入るため）。ローカルからは消す。
  - 段落単位で足す。`lib/zshrc` に既にある行を 1 行ずつ間引かない（`fi`、`}`、`then`、`else` まで抜け、構文が壊れるため）。
  - 同じ設定の段落が複数あるときは、2 で見せたとおり 1 つだけを足す。足さなかった段落も「ローカルから消す」の対象にする。
  - 既存のコメント付きのまとまり（`# 補完`、`# starship`、`# Alias`）の合うところに足す。合うものが無ければ、コメント付きのまとまりを足す。
  - ツールに依存する行は、starship のまとまりと同じ `if command -v <tool> >/dev/null 2>&1; then ... fi` でガードする（README の約束）。
  - `home-path` の行は `/Users/<ユーザー名>` を `$HOME` か `~` に書き換える。引用符の中では `~` が展開されないので `$HOME` にする。
  - `garbage` の行は消す。
  - `zprofile` の段落も `lib/zshrc` に入れる（`lib/zprofile` は作らない）。非対話のログインシェルで効かなくなることは、2 で伝えてある。
  - 足したら `zsh -n lib/zshrc` で構文を確かめる。通らなければ、足した内容を直してから先に進む。
- **ローカルから消す**: ここでは消さない。4 の commit の後で、下の「ローカルから消す」の手順で `~/.zshrc` / `~/.zprofile` から消す。
- **ローカル専用**: 下の「ローカル専用」の手順で、除外リストに `id` を足す。
- **commit（lib）**: ファイルはそのままにして、4 で commit する。取り込み先のファイル（`lib/Brewfile`、`lib/zshrc`）なら、そのエリアの取り込みと同じ commit になる。
- **保留**、**残す**: 何もしない（次回また出る）。

#### 段落の確かめ方

zsh の段落を `lib/zshrc` に足すか、ローカルから消すかを決めるときに使う。`$out` は 1 で残した collect の出力のファイル（シェルの変数は Bash の呼び出しをまたいで残らないので、覚えたパスを書く）。

  - **本文**: 足す内容は、表で見せた `body` を使う。ファイルに取り出したいときは `"$collect_script" --expect-repo "$repo_path" --body "$out" zshrc 12-15 > <ファイル>`。「kind と lines が合う項目がありません」と出たら、`kind` か `lines` の書き間違い。
  - **作業ツリーの `lib/zshrc` にあるか**: 段落のコメントでない行の並びが、作業ツリーの `lib/zshrc` のトップレベルに、同じ順で連続して現れるかを `"$collect_script" --expect-repo "$repo_path" --in-worktree "$out" zshrc 12-15` で見る（`yes` か `no`）。`in-dotfiles` と同じ比べ方を、`HEAD` の代わりに作業ツリーにしたもの（前後の空白を除いて比べる。一部の行だけが別々の場所にあるものや、`if` の中の同じ行は `no`）。

#### ローカルから消す

4 の commit の後で（commit を飛ばしたときも）、共通化した zsh の段落（`in-dotfiles` と、1 つにまとめて足さなかった段落を含む）を `~/.zshrc` / `~/.zprofile` から消す。消す段落は 1 回でまとめて決め、まとめて消す（`lines` は 1 で collect を実行したときの行番号なので、同じファイルから 2 回に分けて消すと、後の回の行番号がずれるため）。

- 消す範囲は `lines` で決める。ファイルの中を `body` や `id` の文字列で探さない（同じ段落が 2 回あると、違うほうや無関係な範囲を消すため）。
- `secret` の項目は共通化を選べないので、ここには来ない（`body` が `***` になっていて、ファイルと一致しない）。
- ファイルの中身を `cat` や `sed` で画面に出さない。比べるのは `collect --check`、行番号は `collect --between`、書き換え後の内容は `collect --without`（リダイレクトする）、見せるのは行番号と下の `diff -U0` だけにする（消さない行に秘密があることがあるため）。
- 消さなかった段落はローカルに残る。消さなかった段落とその理由を伝える。`lib/zshrc` に足して commit した段落なら、設定が 2 回実行されるが、次の実行で `in-dotfiles` として出るので、そのとき消せる（commit しなかった段落は、次の実行でも `lib/zshrc` の変更と zsh の項目として出る）。

先に、消す段落を次の順に決める。

1. **commit**: `in-dotfiles` でない段落（`lib/zshrc` に足した段落、それと 1 つにまとめて足さなかった段落、作業ツリーの `lib/zshrc` に既にあって足さなかった段落）は、4 でその `lib/zshrc` を含む commit が済んだときだけ消す。commit を断ったり失敗したりしたら消さない（設定が `lib/zshrc` の未コミットの変更にしか残らず、次回の「破棄」で失われるため）。`in-dotfiles` の段落（と、それと 1 つにまとめた段落）はリポジトリを変えないので、commit を待たずに消してよい。
2. **読み込み**: `zshrc-sources-lib` が `yes` でなければ（`zshrc-block` が `none` か、どのブロックもこのリポジトリの `lib/zshrc` を読み込んでいないなど）、どの段落も消さない。`~/.zshrc` が `lib/zshrc` を読み込んでいないので、消すと設定が効かなくなる。`lib/zshrc` への取り込みと 4 の commit はそのまま行う。別のターミナル（Terminal.app）で `<リポジトリの絶対パス>/cmd/setup` を実行して読み込む行を足すよう勧める（絶対パスは `git rev-parse --show-toplevel` で求める）。次の実行で、取り込んだ段落が `in-dotfiles` として出るので、そのとき消せる。
3. **作業ツリーの `lib/zshrc`**: `in-dotfiles` の段落は、作業ツリーの `lib/zshrc` にもその段落があるとき（「段落の確かめ方」の `collect --in-worktree` が `yes`）だけ消す。無ければ（この回に commit する `lib/zshrc` の変更でその行を消している）、消すと設定がどこにも残らなくなるので、消さない。
4. **実行順**: 消した段落は、`lib/zshrc` の一部として、`~/.zshrc` の dotfiles ブロック（`zshrc-block`）の位置で実行されるようになる。段落の元の位置とブロックの位置の間で実行される行に、残るコードの行があれば、その行との前後が入れ替わる。そのときは実行順が変わることを見せ、AskUserQuestion で段落ごとに消すかを確認する。おすすめは、段落と間の行が依存しているかで決める:

   - **消す**: 間の行がすべて表の項目の `lines` に入るか、ほかの dotfiles ブロックか `brew shellenv` の段落の行で、どれも段落が設定するもの（変数、`PATH`、`fpath`、関数、alias、`compinit` など）を使わず、段落と同じものを設定してもいない（例: `rbenv init` の段落と、無関係な `alias`）。消さないと、同じ設定が `lib/zshrc` とローカルで 2 回実行されたまま残る。
   - **消さない**: 依存しているか、依存しているか分からないとき（`compinit` より後に `compdef` が走らなくなる、`compinit` より前に `fpath` が足されなくなるなど、順番に頼る設定が壊れるため）。「表に出ていない行」のうち、ほかの dotfiles ブロックと `brew shellenv` の段落以外のもの（除外リストにある段落など）は中身を見られないので、それがあれば消さない。

   おすすめの理由に、どの行とどう関係する（しない）かを書く。間の行は、段落の場所で決まる:

   | 段落 | 間の行 | 消すと |
   |---|---|---|
   | `~/.zshrc` のブロックより前（`lines` の終わり < `zshrc-block` の開始） | `~/.zshrc` の `lines` の終わり + 1 行目から、`zshrc-block` の開始 - 1 行目まで | 間の行より後に実行される |
   | `~/.zshrc` のブロックより後ろ（`lines` の開始 > `zshrc-block` の終わり） | `~/.zshrc` の `zshrc-block` の終わり + 1 行目から、`lines` の開始 - 1 行目まで | 間の行より前に実行される |
   | `~/.zprofile` | `~/.zprofile` の `lines` の終わり + 1 行目から最後の行までと、`~/.zshrc` の 1 行目から `zshrc-block` の開始 - 1 行目まで（`~/.zprofile` は `~/.zshrc` より先に読まれる） | 間の行より後に実行される |

   間の行に残るコードの行が無ければ、実行順の確認はせずに消す（ファイルごとの手順の 4 の `diff -U0` の確認はする）。コードの行は、空行と、`#` で始まる行（前の空白は除く）のほかの行。ほかの dotfiles ブロック（`# >>> dotfiles: homebrew >>>` など）の中の行と、項目にならなかった段落（`brew shellenv` を含むもの、除外リストにあるもの）の行も数える。残るコードの行は、そのうち、この回にそのファイルから消す段落の `lines` に入らないもの。中身を出さずに、行番号だけを出して確かめる（`collect --between <ファイル> <from> <to か end> [skip...]`。`end` なら最後の行まで見る）:

   ```sh
   # ~/.zshrc の 5-7 行目の段落。zshrc-block が 20-22 なので 8-19 行目を見る。この回に ~/.zshrc から消す 12-13 と 15-16 は除く
   "$collect_script" --expect-repo "$repo_path" --between ~/.zshrc 8 19 12-13 15-16
   ```

   - `~/.zshrc` のブロックより後ろの段落: `--between ~/.zshrc <zshrc-block の終わり + 1> <lines の開始 - 1>` で `~/.zshrc` を見る。
   - `~/.zprofile` の段落: 2 回見る。`--between ~/.zprofile <lines の終わり + 1> end` で `~/.zprofile` を見て（`skip` は、この回に `~/.zprofile` から消す段落の `lines`）、`--between ~/.zshrc 1 <zshrc-block の開始 - 1>` で `~/.zshrc` を見る（`skip` は、この回に `~/.zshrc` から消す段落の `lines`）。
   - `skip` は `lines` を空白区切りで並べる。無ければ省く。

   行番号が出たら確認する。見せるのは、消す段落（表の番号と `lines`）、ブロックの位置、出た行がどのファイルの何行目で、どの項目の `lines` に入るか。どの項目にも入らない行は「表に出ていない行」とだけ書き、中身は出さない（除外リストにある秘密の段落のことがあるため）。例: 「#4（`~/.zshrc` 5-7 行目）を消すと、`lib/zshrc` を読み込む 20-22 行目で実行されるようになり、間に残る 10 行目（#6、保留）より後になる」「#8（`~/.zshrc` 29-30 行目）を消すと、20-22 行目で実行されるようになり、間に残る 27 行目（#7、保留）より前になる」。確認で消さないことにした段落があれば、その `lines` を `skip` から外し、まだ決めていない段落を確かめ直す。

   例（`~/.zshrc` の 5-7、12-13、15-16、24-25、29-30 行目と `~/.zprofile` の 2-4 行目の段落を共通化し、`~/.zshrc` の 10 行目と 27 行目の段落は保留。`~/.zshrc` のほかの行（1-4、8-9、11、14、17-19、23、26、28 行目）は空行かコメントだけ。`~/.zprofile` の 1、5 行目は空行、6 行目は `brew shellenv` の段落）:

   | `zshrc-sources-lib` | `zshrc-block` | 段落の `kind` と `lines` | 間に残るコードの行 | 判断 |
   |---|---|---|---|---|
   | `no` | `none` | `zshrc` `5-7` | （見ない） | 消さない。`cmd/setup` を勧める |
   | `yes` | `20-22` | `zshrc` `5-7` | 8-19 行目のうち 10 行目（12-13 と 15-16 は消すので数えない） | 消すかを確認する。おすすめは間の行との依存で決める |
   | `yes` | `20-22` | `zshrc` `12-13` | 14-19 行目には無い（14 行目は空行、15-16 は消す、17-19 は空行とコメント） | 実行順の確認をせずに消す |
   | `yes` | `20-22` | `zshrc` `24-25` | 23 行目には無い（空行） | 実行順の確認をせずに消す |
   | `yes` | `20-22` | `zshrc` `29-30` | 23-28 行目のうち 27 行目（24-25 は消すので数えない） | 消すかを確認する。おすすめは間の行との依存で決める |
   | `yes` | `20-22` | `zprofile` `2-4` | `~/.zprofile` の 5 行目から最後までのうち 6 行目と、`~/.zshrc` の 1-19 行目のうち 10 行目 | 消すかを確認する。おすすめは間の行との依存で決める |

消すと決めた段落について、ファイルごとに次を行う。

1. 消す段落の `lines` の範囲の内容が `body` と一致することを確かめる。`collect --check` に、1 で残した出力のファイル、`kind`、ファイル、消す段落の `lines` をすべて渡す（範囲ごとに `一致` か `不一致` が出る。中身は出ない）。

   ```sh
   "$collect_script" --expect-repo "$repo_path" --check "$out" zshrc ~/.zshrc 12-15 30-31
   ```

   1 つでも不一致なら（終了コード 1）、collect を実行した後にファイルが変わっている。ファイルを書き換えずに、3 で `zsh -n` が通らないときと同じように流れ全体を止める（collect を実行し直して、もう一度選んでもらう必要がある）。
2. 段落を除いた内容を一時ファイル（`mktemp`）に作る。`collect --without` に、消す段落の `lines` をすべて渡し、標準出力を一時ファイルにリダイレクトする（まとめて除くので、順番も行番号のずれも気にしなくてよい。消した段落の前後の空行は重なって残るが、内容には影響しない）。元のファイルは書き換わらない。

   ```sh
   tmp="$(mktemp)"; "$collect_script" --expect-repo "$repo_path" --without ~/.zshrc 12-15 30-31 > "$tmp"
   ```

3. `zsh -n <一時ファイル>` で構文を確かめる。通らなければ（段落の境目が `if` や関数の途中にあるなど）、ファイルを書き換えずに流れ全体を止める（残りのファイル、4 の最後の collect での確認、5 の push に進まない。4 の commit は済んでいる）。エラーの内容、そのファイルは書き換えていないこと、ここまでに済んだこと（commit したもの、まだ push していないこと）を伝え、ターンを終えてユーザーの指示を待つ。元のファイルも `zsh -n` で確かめ、元から通らないならそのことも伝える。
4. `diff -U0 <ファイル> <一時ファイル>` を見せ、AskUserQuestion で消すかを確認する。前後の行を出さないよう `-U0` にする（除外リストにある `secret` の段落は collect の出力に出ないが、ファイルには残っているため）。
5. 消すなら、バックアップと書き換えを同じ lock 内で行う。退避先を伝える。

   ```sh
   "$lock_script" "$repo_path" -- bash -s -- "<ファイル>" "<一時ファイル>" <<'SH'
   set -eu
   file="$1"; tmp="$2"
   [ -f "$file" ] && [ -r "$file" ] || { echo "元ファイルを読めません: $file" >&2; exit 1; }
   [ -f "$tmp" ] && [ -r "$tmp" ] || { echo "一時ファイルを読めません: $tmp" >&2; exit 1; }
   stamp="$(date +%Y%m%d%H%M%S)"
   backup="$(mktemp "$file.backup-$stamp.XXXXXX")" || exit 1
   stage="$(mktemp "$file.tmp.XXXXXX")" || { rm -f "$backup"; exit 1; }
   if ! cp -p "$file" "$backup"; then rm -f "$backup" "$stage"; echo "バックアップに失敗しました: $file" >&2; exit 1; fi
   if ! cp -p "$file" "$stage" || ! cat "$tmp" > "$stage"; then rm -f "$stage"; echo "一時ファイルを反映できませんでした: $file" >&2; exit 1; fi
   if ! mv -f "$stage" "$file"; then rm -f "$stage"; echo "置き換えに失敗しました。元ファイルを保持しました: $file" >&2; exit 1; fi
   echo "バックアップ: $backup"
   SH
   ```

#### ローカル専用

除外リスト `${DOTFILES_IGNORE_FILE:-$HOME/.config/dotfiles/ignore}` の末尾に、ローカル専用にした項目の `id` を 1 行ずつ足す。

- `id` は collect の出力の `id: ` の後ろをそのまま使い、`body` から作り直さない（`secret` の項目の `id` は `<kind>:sha256:...` なので、秘密情報が除外リストに書き写されない）。
- ディレクトリが無ければ作る。ファイルの末尾が改行で終わっていなければ、前の行と `id` がつながらないよう、先に改行を足す。
- `id` には `$` や引用符が入るので、展開しない形（`<<'EOF'`）で書く。`id` の行と `EOF` の行は字下げしない（`EOF` の行が字下げされているとヒアドキュメントが閉じず、`id` の先頭にも空白が入って一致しなくなる）。

```sh
"$lock_script" "$repo_path" -- bash -s <<'SH'
f="${DOTFILES_IGNORE_FILE:-$HOME/.config/dotfiles/ignore}"
mkdir -p "$(dirname "$f")"
if [ -s "$f" ] && [ -n "$(tail -c 1 "$f")" ]; then echo >> "$f"; fi
cat >> "$f" <<'EOF'
zshrc:alias gcomi='(){~/Script/cmd/commit $1}'
brew:mysql
EOF
SH
```

すべての選択を反映したら、次に進む。

### 4. commit

commit するかは、3 でリポジトリのファイルを変えたか（取り込み、dotfiles から削除、`lib` の commit）で決める。変えたものが無ければ、commit を飛ばして 3 の「ローカルから消す」に進む。保留にした `lib` の変更（iTerm2 の plist など）は残るので、`git status` が空かどうかでは決めない。

1. 3 で覚えたファイルの差分を、`"$collect_script" --expect-repo "$repo_path" --diff <パス>...` で見せる（未追跡のファイルは中身が出る）。生の `git diff` は使わない（消された行や文脈の行にある秘密の値が、チャットに出るため。`collect --diff` は、秘密と判定した値を `***` にして出す）。plist は変更の要約が出るので、長ければ抜粋し、全文は聞かれたら見せる（`git -C "$repo_path" diff --stat -- <パス>` は見せてよい）。AskUserQuestion で commit するかを確認する。
2. エリアごとに 1 commit にする（Brewfile、zsh、`lib/` の変更はファイルごと）。そのエリアのファイルだけを `main` に直接 commit する。`git commit` にパスを付け、ほかに stage されているもの（保留にした `lib` の変更など）を含めない。未追跡のファイルは `git add` しないと `git commit -- <パス>` が失敗するので、先に `git add` する:

   ```sh
   "$lock_script" "$repo_path" -- git -C "$repo_path" add -- <パス>...
   "$lock_script" "$repo_path" -- git -C "$repo_path" commit -m '<メッセージ>' -- <パス>...
   ```

3. メッセージは `[feat]` `[fix]` `[del]` + 日本語の要約。例: `[feat] Brewfile に actionlint などを追加`、`[feat] zshrc に rbenv の初期化を追加`、`[del] Brewfile から gitkraken を削除`、`[feat] iTerm2 の設定を更新`。

commit を断ったり失敗したりしたら（フックで止まったなど）、そのことを伝え、そのエリアのファイルは commit せずに残す。`lib/zshrc` の commit なら、`in-dotfiles` でない段落はローカルから消さない（「ローカルから消す」の「commit」）。ほかのエリアの commit と、ローカルから消す手順は続ける。

commit を終えたら（飛ばしたときも）、3 の「ローカルから消す」の手順で段落を消す。その後 `"$collect_script" --expect-repo "$repo_path" --no-fetch` を実行し直し、残っている項目が、保留・残すにしたもの、commit を断ったか失敗したもの（そのファイルの `lib` の項目と、取り込んだ段落）、ローカルから消さなかった段落（`zshrc-sources-lib` が `yes` でなかったもの、作業ツリーの `lib/zshrc` に無かった `in-dotfiles` のもの、実行順や `diff -U0` の確認で断ったもの）だけであることを確かめる。

### 5. push

ツールの追加を頼まれていれば、先に「ツールの追加」を行う。

push するもの（1 の `ahead` が 1 以上か `unknown`、またはこの実行でした commit）が無ければ、push の確認を飛ばして終わる。あれば、AskUserQuestion で `origin main` に push するかを聞く。おすすめは「push する」。push するなら `"$lock_script" "$repo_path" -- git -C "$repo_path" push origin main`。拒否されたら（origin が先に進んでいるなど）、そのことを伝えて止める。

## ツールの追加

起動時の引数か会話でツールを管理に加えるよう頼まれたときだけ行う。差分の確認（流れの 1〜4）が済んでから行い、push は流れの 5 で最後に 1 回だけ聞く。

1. **反映方法を提案する**: ツールの設定ファイルの場所を調べ、方法を提案して AskUserQuestion で確認する。
   - 原則はシンボリックリンク（starship と同じ）: 2 で設定ファイルを `lib/` にコピーし、元のファイルは 4 で `cmd/setup` の `link_file` が退避して、`lib/` のファイルへのリンクにする。以後のローカルの変更は、`lib` の未コミットの変更として流れの 2 に出てくる。
   - Mac ごとの値や秘密情報が混ざるファイルは、ツールの include 機能を使う（例: git は `~/.gitconfig` に `[include] path = <リポジトリ>/lib/gitconfig`）。シンボリックリンクにすると、秘密情報を除いた内容でローカルのファイルが置き換わるため。共通の部分だけを `lib/` に置き、ローカルのファイルに残りを残す。
   - ツールが設定を書き換えるときに、リンクを保つか（普通のファイルに置き換えないか）を、ドキュメントや既知の issue で確かめる。保たないなら include など別の方式にする。
2. **README の「ツールを追加する」の手順で足す**:
   - 設定ファイル（include 方式なら共通の部分）を `lib/` にコピーする。コピーは `"$lock_script" "$repo_path" -- cp -p "<元ファイル>" "$repo_path/lib/<ファイル>"` で行う。元のファイルはそのまま残す（シンボリックリンクなら 4 で置き換わる）。秘密情報（「おすすめの決め方」の `secret` に当たる行）と `garbage` に当たる行は `lib/` に入れない。秘密情報があるファイルは、1 で include 方式にする。ファイルの中身を見せるときは、秘密の値を `***` に置き換える。
   - `cmd/setup` に冪等な `setup_<tool>` を足し、末尾の手順の並びに `step` と呼び出しを足す（`setup_starship` のように `cmd/common.sh` の `is_linked` / `link_file` を使う）。
   - `lib/<tool>.md` を書き、README の表に 1 行足す。
3. **collect に検出を足す**: include 方式のように `lib` の変更として出てこないものは、そのツールの差分を集める処理を `collect` に足し、ほかの項目と同じ `=== item` の形式で出す（`kind` は新しい名前、`id` は `<kind>:<識別子>`）。`shellcheck` を通す。VS Code を加えるときは、Brewfile の `vscode` 行（拡張機能）の検出もここで足す。
4. **setup を実行してもらう**: スキル内から実行すると、`cmd/setup` の `ask_yes_no` に答えられず、入力の終わり（EOF）が No として扱われてすべてスキップされる。ユーザーに別のターミナル（Terminal.app）で `<repo_path>/cmd/setup --expect-repo "<repo_path>"` を実行してもらう。この checked mode は shared lock 内で repo pointer と移行 marker を検証してから設定を変更し、setup 内の `install_skills` はその lock を検証して借りる。pointer が変わっている場合は設定を変更せずに終了するので、collect と選択からやり直す。
   - 絶対パスは `git rev-parse --show-toplevel` で求め、コピーしてそのまま実行できるコマンドの形で伝える。ターンを終え、終わったと言われるのを待つ。
   - 終わったと言われたら、ローカルのファイルがリンク（または include）に切り替わったことを `ls -l` などで確かめる。切り替わっていなければ、`cmd/setup` の最後に出たスキップと失敗を聞き、直してからもう一度実行してもらう。
5. **commit**: 流れの 4 と同じやり方（`git add <パス>...` の後に `git commit -m '<メッセージ>' -- <パス>...`）で、ツールごとに 1 commit にする（例: `[feat] VS Code の設定を管理に加える`）。その後、流れの 5 の push の確認に戻る。
