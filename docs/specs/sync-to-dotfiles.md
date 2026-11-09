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
| `brew` | `brew list --formula --installed-on-request`（ほかの formula の依存になっていても、自分で入れたものは出す） | `lib/Brewfile` の `brew "..."` |
| `cask` | `brew list --cask` | `lib/Brewfile` の `cask "..."` |
| `tap` | `brew tap` | `lib/Brewfile` の `tap "..."` |
| `zshrc` | `~/.zshrc` の dotfiles ブロックの外 | `HEAD` の `lib/zshrc` |
| `zprofile` | `~/.zprofile` の dotfiles ブロックの外 | `HEAD` の `lib/zshrc` |
| `lib` | リポジトリの `lib/` 以下の未コミットの変更（未追跡のファイルを含む） | `HEAD` |

- brew コマンドは `HOMEBREW_NO_AUTO_UPDATE=1` で呼ぶ。brew が無ければ `brew` `cask` `tap` を飛ばし、`warn` を出す。
- 逆向きの差分も出す: Brewfile にあるのにインストールされていないもの。`brew` はインストール済みかを `brew list --formula`（依存として入ったものも含む）で判定する。
- `brew` と `cask` は名前の最後の `/` より後ろで比べる（tap のフォーミュラは完全な名前と短い名前が混ざるため）。`tap` は名前全体で比べる。`homebrew/core` と `homebrew/cask` は出さない。Brewfile の完全な名前の行（`brew "user/tap/foo"`）から暗黙に追加される tap は、Brewfile にあるものとして扱う（ローカル側の項目を出さないためだけに使い、逆向きの差分には出さない。消せる `tap` の行が無いため）。
- dotfiles 側（`lib/Brewfile` と `lib/zshrc`）は `HEAD` の内容と比べる（`git show HEAD:<パス>`）。作業ツリーの未コミットの変更は `lib` の項目として別に出る。作業ツリーと比べると、未コミットの変更にしかない行が「dotfiles にある」と判定され、その変更を破棄したときに設定がどこにも残らなくなるため。
- サードパーティの tap のもの（`homebrew/core` と `homebrew/cask` 以外）は、`body` と `id` に完全な名前（`<user>/<tap>/<名前>`。`brew list --formula --installed-on-request --full-name` / `brew list --cask --full-name`）を出す。Brewfile に短い名前で書くと、新しい Mac の `brew bundle` が失敗するため。
- dotfiles ブロック: `# >>> dotfiles` で始まる行から `# <<< dotfiles` で始まる行まで（`dotfiles: homebrew` のような名前付きも含む）。閉じていなければ開始行から最後までを除き、`warn` を出す。
- `zprofile` では `brew shellenv` を含む行も除く（dotfiles ブロック導入前に追記されたもの）。その行を除いた残りが `zsh -n` を通らないか、制御構文の行（`if` `then` `else` `fi` `{` `}` など）とコメントだけになる段落は、段落ごと除く（`if ...; then eval "$(brew shellenv)"; fi` から中身のない `if` が出ないため）。段落をつなぐかは `brew shellenv` の行を含めた元の内容で決め、行を除くのはつないだ後にする。`lines` は除いた後の最初の行から最後の行まで（途中の `brew shellenv` の行は範囲に入る）。
- `zshrc` と `zprofile` は、空行で区切った「段落」を 1 項目にする。空行には空白だけの行も含めるが、100 文字以上の空白だけの行は段落に残す（§6 の `garbage`）。dotfiles ブロックも段落の区切りになる。コメントだけの段落と空の段落は出さない。
- 段落がそれだけで構文として完結しない（`zsh -n` が通らない）ときは、通るまで次の段落とつなぐ（`if` や関数の中の空行で、`fi` や `}` だけの断片ができないようにするため）。閉じていないヒアドキュメント（`<<EOF` などの終わりの行がまだ無い）と、最後のコメントでない行が `\` `&&` `||` `|` で終わる段落も、`zsh -n` が通っても完結していないものとしてつなぐ（`zsh -n` はファイルの終わりでこれらを通すため）。dotfiles ブロックを越えてはつながない。ファイルの最後か dotfiles ブロックの手前までつないでも通らなければ、そこまでを 1 項目にして `warn` を出す。
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
lines: 3-3
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

- `=== repo`: `branch` は現在のブランチ（detached HEAD なら `HEAD`）。`behind` と `ahead` は `refs/remotes/origin/<branch>` との差のコミット数。fetch に失敗したとき、`origin/<branch>` が無いとき、detached HEAD のときは `unknown` にし、理由を `warn` に出す。`dirty` は `lib/` 以外の未コミットの変更（未追跡を含む）で、1 ファイル 1 行、無ければ行を出さない。
- `=== item`: 差分 1 件。
  - `kind`: §4 の種類。
  - `id`: 除外リスト（§7）で使う識別子。`<kind>:<識別子>` の形。`brew` `cask` `tap` は名前、`zshrc` `zprofile` は段落のコメントでない行を前後の空白を除いて ` ⏎ ` でつないだもの（1 行の段落ならその行。段落の中身が変われば別の項目として扱う）、`lib` はリポジトリからの相対パス。`secret` が立つ `zshrc` `zprofile` の項目は、秘密情報を除外リストに書き写さないよう `<kind>:sha256:<上の文字列の SHA-256>` にする（末尾に改行を付けない文字列から求める）。
  - `lines`: `zshrc` `zprofile` だけ。`id` の次の行に出す。段落がファイルの何行目から何行目か（`lines: 12-15`。1 から数える）。skill はこの範囲でローカルの段落を消す（同じ内容の段落が複数あっても取り違えないため）。
  - `direction`: `local`（ローカルにだけある）、`dotfiles`（dotfiles にだけある）、`changed`（`lib/` の未コミットの変更）のどれか。
  - `flags`: §6 のフラグを、§6 の表の順にカンマ区切りで。無ければ `-`。
  - `body:` の後: 本文。各行の先頭に 4 スペースを付ける。`brew` `cask` `tap` は名前、`zshrc` `zprofile` は段落の全文、`lib` は §5.1 の要約。`secret` が立つ項目は、秘密と判定した値を `***` に置き換える（表に載せたときにチャットや transcript に残さないため）。`lib` の diff では、足された行だけでなく、消された行と前後の文脈の行も同じ条件で置き換える。
- `=== warn`: 確認できなかったこと（1 行 1 件）。無ければブロックを出さない。
- `=== summary`: `items`（出した項目数）と `ignored`（除外リストで除いた数）。
- オプション: `--no-fetch`（`git fetch` しない。`behind` と `ahead` はローカルの追跡ブランチで数える）。
- テストのために `HOME` と `PATH` を差し替えて動くようにする（`~` は `$HOME` で解決し、brew は `PATH` から探す）。除外リストの場所は環境変数 `DOTFILES_IGNORE_FILE` で差し替えられる。
- リポジトリの場所は collect 自身の場所から求める（`.claude/skills/sync-to-dotfiles/scripts/` の 4 つ上）。
- 終了コード: 出力できたら 0。リポジトリが見つからないなど、出力できなかったら 1。

### 5.1 `lib` の要約

- `.plist`: 変わったキーのパスと、前後の値（80 文字を超える値は省略）。`HEAD` の内容と作業ツリーの内容を比べる。どちらかを plist として読めない（新規、削除、壊れている）ときは `git diff` にする。配列の要素が `Guid` キーを持つ辞書（iTerm2 のプロファイルなど）なら、位置ではなく `[Guid=<値>]` で識別する（要素の削除や並べ替えで、後ろの要素がすべて変わったように見えないため）。同じ配列で `Guid` が重なる要素は位置で識別する。本文とフラグは、plist を 1 回だけ読んだ結果から作る。
- それ以外: `git diff` の内容。未追跡のファイルは先頭 200 行。
- どれも 200 行を超えたら省略し、省略したことを書く。
- 状態を表す補助の行を先頭に付けてよい: `(未追跡のファイル)`、`(バイナリファイル)`、`(空のファイル)`、`(シンボリックリンク: …)`、`(HEAD との差分はありません)` など。

## 6. フラグ

| フラグ | 条件 | skill のおすすめ |
|---|---|---|
| `home-path` | `$HOME` の絶対パス（`/Users/<ユーザー名>/...`）を含む | 共通化。取り込むときに `$HOME` か `~` に書き換える |
| `missing-path` | `~/...`、`$HOME/...`、`${HOME}/...`、`/Users/...` のパスで、存在しないものを参照している（引用符で囲んだパスと `\ ` でエスケープした空白は、パスの一部として扱う） | ローカル専用 |
| `secret` | トークンらしい文字列を含む（下の条件） | 共通化を選べない。ローカル専用か保留だけ |
| `garbage` | 1000 文字以上の行、または 100 文字以上の空白だけの行がある | 取り込むときにその行を消す |
| `in-dotfiles` | 段落のコメントでない行が、すべて `HEAD` の `lib/zshrc` に既にある（前後の空白を除いて比べる） | 共通化（dotfiles にあるので、ローカルから消すだけ） |

フラグを付ける種類: `brew` `cask` `tap` には付けない。`zshrc` `zprofile` には 5 種すべて。`lib` には `in-dotfiles` 以外の 4 種を、足された内容（diff の `+` 行、未追跡のファイル全体、plist の変更後の値）だけで判定する。

`lib` の項目では、`secret` があれば commit を選べない（破棄か保留だけ。おすすめは保留）。ほかのフラグは理由に書くだけで、書き換えはしない。

`secret` の条件は次のどれか:

- 変数への代入（行の中の `NAME=値` の形の単語。`export` `sudo` `env` の引数、`;` `{` `then` `if` の後なども含む。`alias` の引数（次の `;` `&` `|` `(` `)` `#` まで）と `[[ ... ]]` の中は代入ではない）で、変数名が `TOKEN` `SECRET` `PASSWORD` `PASSWD` `API_KEY` `APIKEY` `PRIVATE_KEY` `CREDENTIAL` を含むか、`_KEY` で終わるもの（大文字小文字は区別しない）。値が `$` で始まるもの（`"$(gh auth token)"` など）、空の値、パス（`~` か `/` で始まる）、真偽値や数値だけの値（`true` `false` `yes` `no` `0` など）は除く（`SSH_KEY=~/.ssh/id_rsa` や `TOKENIZERS_PARALLELISM=false` や `MAX_TOKENS=4096` で共通化を選べなくならないため）。ただし数値だけの値の除外は、名前が `PASSWORD` `PASSWD` `SECRET` を含むときは行わない（`PASSWORD=12345`）。`$` の除外は、単一引用符で囲んだ値（`'$abc123'` は展開されない文字列）には行わない。
- 設定ファイル形式の `キー: 値`、`キー = 値`、`"キー": "値"` で、キーが上と同じ条件に当たり、値も上と同じ除外に当たらないもの（`lib` の YAML / TOML / JSON のため）。コメントの行（`#` `;` で始まる。`//` で始まる行は `.npmrc` の `//registry.npmjs.org/:_authToken=...` があるのでコメントとみなさない）、`{` か `[` で始まる値、`""` で囲んだキーに `""` で囲んでいない値が付くもの（JSON の `null` など）は見ない。キー名のハイフン（`api-key`）は条件に当たらない（既知の制限）。plist は変更後の値だけで判定し、キーの名前は見ない。
- `ghp_` `gho_` `github_pat_` `npm_` `glpat-` `AIza` `sk-` `sk_live_` `rk_live_` `xox?-` `AKIA` で始まる値、`Bearer <トークン>`（16 文字以上）、`_authToken=<値>`（8 文字以上。どちらも `$` で始まる値は除く。`.npmrc` の `_authToken=${NPM_TOKEN}` は普通の書き方のため）、`-----BEGIN ... PRIVATE KEY-----`。単語の先頭で、ある程度の長さが続くものだけにする（`disk-` などに誤って反応しないため）。
- URL の中の認証情報（`://<ユーザー>:<パスワード>@`。パスワードが `$` で始まるものは除く）。

複数のフラグが立ったときは `secret` > `in-dotfiles` > `missing-path` > `home-path` の順に優先する。`garbage` は、おすすめとは別に「取り込むときにその行を消す」という但し書きとして扱う。

## 7. 除外リスト

- 場所: `~/.config/dotfiles/ignore`。Mac ごとに持ち、リポジトリには入れない。
- 形式: 1 行に 1 つ、§5 の `id` をそのまま書く。空行と `#` で始まる行は無視する。行末の空白と CR は取り除いてから比べる（手で編集したときに一致しなくならないため）。
- collect は、`id` が完全に一致する項目を出さず、`ignored` に数える。`lib:` で始まる行は無視し、`warn` を出す（`lib` の項目はローカル専用を選べない。隠すと、その未コミットの変更が取り込みの commit に混ざるため）。ファイルが無ければ除外なしとして扱う。
- skill は、ユーザーが「ローカル専用」にした項目の `id` を `${DOTFILES_IGNORE_FILE:-$HOME/.config/dotfiles/ignore}` に追記する（ディレクトリが無ければ作る。ファイルの末尾が改行で終わっていなければ、先に改行を足す）。

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
   - 項目が 0 件なら、そう伝えて 3 と 4 を飛ばし、5 に進む（§9 の依頼があればそれを行う。push するものが無ければ終わる）。
3. **反映**:
   - Brewfile: 既存のセクション（`# CLI`、`# アプリ`、`# フォント`）の適切な場所に足す。合うものが無ければセクションを足す。「dotfiles から削除」は行を消す。
   - 順序: `lib` の「破棄」を最初に行い、その後に Brewfile と zsh の取り込みを行う（後から破棄すると、取り込んだ内容まで消えるため）。
   - 取り込み先のファイル（`lib/Brewfile`、`lib/zshrc`）が `lib` の項目にもなっていて、この回にそのファイルへの取り込みがあるときは、その `lib` の項目を commit か破棄にするか、そのファイルへの取り込みもこの回は保留にするかを選んでもらう（保留の変更が取り込みの commit に混ざるため）。`secret` で commit できない項目なら、破棄か、取り込みの保留のどちらか。表の選択が決まった後に AskUserQuestion で聞き、おすすめは「取り込みも保留」（何も失われないため）。「そのファイルへの取り込み」には、`lib/Brewfile` では「dotfiles から削除」も含め、`lib/zshrc` では `in-dotfiles` の段落（ローカルから消すだけ）は含めない。取り込みを保留にしたら、そのファイルに足す・消す項目と、まとめた段落もこの回は保留にする。
   - zsh: `lib/zshrc` に段落単位で足す。行単位で間引かない（`fi` や `}` が抜けるため）。同じ設定の段落が複数ある（例: `zshrc` と `zprofile` の `rbenv init`）ときは 1 つにまとめ、どれを残すかを見せる。この回に commit する `lib/zshrc` の未コミットの変更に、同じ段落が既にあれば足さない（二重に入るため。Brewfile の行も同じ。作業ツリーで既に消してある行の「dotfiles から削除」は何もしない）。ツールに依存する行は `command -v <tool>` でガードする（README の約束）。`home-path` は `$HOME` か `~` に書き換え、`garbage` の行は消す。`zprofile` から取り込むものも `lib/zshrc` に入れる（`lib/zprofile` は作らない）。`lib/zshrc` は対話シェルでしか読まれないので、`zsh -l -c` のような非対話のログインシェルでは効かなくなるが、ユーザーの決定としてこの差は受け入れる。
   - 取り込んだ（または `in-dotfiles` だった）段落は、ローカルの `~/.zshrc` / `~/.zprofile` から消す。`in-dotfiles` の段落は、作業ツリーの `lib/zshrc` にもその行があるときだけ消す（この回に commit する変更がその行を消していると、設定がどこにも残らないため）。消す範囲は `lines` で決め、その範囲の内容が `body` と一致することを確かめてから消す（一致しなければ流れ全体を止める。ファイルが変わっているため）。比べる `body` は、1 で一時ファイルに残した collect の出力から `kind` と `lines` で取り出す。消す前に差分を `diff -U0` で見せて確認し（前後の行に、除外した秘密の段落が出ないようにするため）、`<ファイル>.backup-YYYYmmddHHMMSS` に退避する。書き換える前に、書き換え後の内容を `zsh -n` で確かめ、通らなければ書き換えずに流れ全体を止め（残りのファイル、除外リストへの追記、commit、push に進まない）、ユーザーの指示を待つ（リポジトリ側の変更は commit せずに残り、先に済んだファイルの書き換えは退避ごと残る）。`zprofile` の段落は `brew shellenv` の行を除いているのでファイルの中で連続しないことがある。消す範囲の中の `brew shellenv` の行は残す。
   - `lib` の「破棄」は `git restore --source=HEAD --staged --worktree`（stage した変更も戻すため。未追跡なら削除）。iTerm2 の plist は、iTerm2 が起動中だと終了時に書き戻されることを伝える。
   - 「ローカル専用」は除外リストに追記する。「保留」は何もしない（次回また出る）。
4. **commit**: commit するかは、3 でリポジトリのファイルを変えたか（取り込み、dotfiles から削除、`lib` の commit）で決める。保留にした `lib` の変更は残るので、`git status` が空かどうかでは決めない。変えたものが無ければ commit を飛ばして 5 に進む。commit は `git commit -- <パス>` でそのエリアのファイルだけにする（ほかに stage されているものを含めないため）。`git diff` を見せて確認してから、エリアごとに分けて `main` に直接 commit する（個人用の dotfiles なのでブランチや PR は作らない）。メッセージは `[feat]` `[fix]` `[del]` + 日本語（例: `[feat] Brewfile に actionlint などを追加`）。
5. **push**: push するもの（1 の `ahead` が 1 以上か `unknown`、またはこの実行でした commit）が無ければ、確認を飛ばして終わる。あれば AskUserQuestion で `origin main` に push するかを聞く。おすすめは「push する」。

## 9. ツールの追加

ユーザーが引数か会話でツールの追加を頼んだときだけ行う。§8 の差分の確認の後に行う。

1. 反映方法をツールごとに提案し、確認する:
   - 原則はシンボリックリンク（設定ファイルを `lib/` にコピーし、元のファイルは `cmd/setup` の `link_file` が退避してリンクにする。starship と同じ）。以後のローカルの変更は `lib` の未コミットの変更として §8 で出てくる。
   - Mac ごとの値や秘密情報が混ざるファイルは、ツールの include 機能を使う（例: git は `~/.gitconfig` に `[include] path = .../lib/gitconfig`）。シンボリックリンクにすると、秘密情報を除いた内容でローカルのファイルが置き換わるため。
   - ツールがシンボリックリンクを保つか（書き換えるときにリンクを普通のファイルに置き換えないか）を確かめ、保たないなら別の方式にする。
2. 1 で決めた方式で、README の「ツールを追加する」の手順で行う: 設定ファイルを `lib/` に置く、`cmd/setup` に冪等な `setup_<tool>` を足して手順の並びに加える、`lib/<tool>.md` を書く、README の表に 1 行足す。
3. include 方式のように `lib` の変更として出てこないものは、そのツール用の検出を `collect` に足す（§5 の形式で出す）。
4. 秘密情報（§6 の `secret`）と壊れた内容（`garbage`）は取り込まない。
5. ユーザーに別のターミナル（Terminal.app）で `<リポジトリ>/cmd/setup` を実行してもらい（Claude Code の `!` では `cmd/setup` の質問に答えられないため）、ローカルのファイルがリンクなどに切り替わったことを Claude が確認してから、§8 の 4、5 で commit と push をする。

## 10. README

「ローカルの変更を取り込む」節を足す:

- dotfiles リポジトリで Claude Code を起動し、`/sync-to-dotfiles` を実行する。ツールを管理に加えたいときは引数で伝える。
- 除外リストの場所（`~/.config/dotfiles/ignore`）と形式。
- 新しいツールを追加した後は `cmd/setup` を実行し直す。

「構成」に `.claude/skills/sync-to-dotfiles/` を足す。

## 10.1 既知の制限

- 段落が閉じないまま続くと、つなぐたびに `zsh -n` をかけ直すので、処理時間が段落の数の 2 乗で増える。`~/.zshrc` の大きさでは問題にならない。
- 設定ファイル形式の `secret` は、キー名のハイフン（`api-key`）に当たらない。

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
