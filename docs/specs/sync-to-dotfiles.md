# sync-to-dotfiles 仕様書

この Mac の設定と dotfiles リポジトリの差分を集め、共通化したいものだけを dotfiles に取り込む Agent Skill。Claude Code と Codex は同じ plugin copy を使う。
`cmd/setup`（dotfiles → この Mac）と逆向きの入口。実行時の repo は `~/.config/dotfiles/repo` から読み、canonical absolute path のみ受け付ける。

## 1. 範囲

- 見るのは、dotfiles が既に管理している範囲だけ（§4）。skill が自分で新しい候補を探すことはしない。
- 新しいツールを管理に加えるのは、ユーザーが引数か会話で頼んだときだけ（§9）。
- 範囲外: npm のグローバルパッケージ、macOS の defaults、`~/.ssh/config`、`~/.rbenv/version`、`~/.config/gh/config.yml`、Claude Code の設定（ユーザーが §9 で頼めば追加できる）。
- VS Code は、この skill を main に入れた後の最初の実行で §9 の手順で取り込む。この skill の実装には含めない。

## 2. ファイル構成

```
lib/agents/nozimin/skills/sync-to-dotfiles/
  SKILL.md         流れ、判断のルール、表の出し方、反映の手順
  scripts/collect  差分を集めて決まった形式で出す（bash、実行権限付き）
```

- この場所を Claude Code 形式 plugin `nozimin` として Claude Code / Codex にインストールする。追加・変更後は `cmd/install_skills` を実行して Codex の cache を更新する。
- 言語は日本語（SKILL.md、collect のコメントとメッセージ）。既存の `cmd/setup` と `cmd/common.sh` の書き方に合わせる。
- `collect` は読み取り専用。書き込みは `git fetch` だけ。ファイルの編集、commit、push は SKILL.md の手順で Agent が行う。
- `collect` には、SKILL.md が Agent に `awk` / `sed` を手で書かせずに済むよう、読み取り専用のサブモードがある（§5.2）。どれも結果を標準出力だけに出し、ファイルの中身（秘密を含みうる）を画面に出さない形にする。SKILL.md はこれらを呼ぶだけにし、collect の `LC_ALL=C` と食い違うロケールの `awk` / `sed` を手順に書かない。

## 3. 起動

- frontmatter: `name: sync-to-dotfiles`、`disable-model-invocation: true`、`argument-hint`（例: `[追加したいツール]`）、description は日本語。Codex の `agents/openai.yaml` でも implicit invocation を無効にする。
- Claude Code では `/nozimin:sync-to-dotfiles`、Codex CLI では `/skills` の一覧から `$nozimin:sync-to-dotfiles` を選んで手動起動する。どちらも明示的に呼び出したときだけ動く。
- 引数（任意）: 管理に加えたいツール（例: `/nozimin:sync-to-dotfiles VS Code も入れて` または `$nozimin:sync-to-dotfiles VS Code も入れて`）。引数なしなら差分の確認だけ。

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
- `brew` と `cask` は名前の最後の `/` より後ろで比べる（tap のフォーミュラは完全な名前と短い名前が混ざるため）。Brewfile の名前が別名や古い名前（`postgresql` → `postgresql@14` など）のときは、`brew info --json=v2 --installed` の `aliases` / `oldnames`（cask は `old_tokens`）で、インストール済みの名前に読み替えてから比べる（`jq` が無ければ読み替えず、`warn` を出す。読み替えが要るとき、つまり Brewfile にインストールされていない名前があるときだけ `brew info` を呼ぶ）。brew は `PATH` に無ければ `cmd/common.sh` の `load_brew` で探す。`tap` は名前全体で比べる。`homebrew/core` と `homebrew/cask` は出さない。Brewfile の完全な名前の行（`brew "user/tap/foo"`）から暗黙に追加される tap は、Brewfile にあるものとして扱う（ローカル側の項目を出さないためだけに使い、逆向きの差分には出さない。消せる `tap` の行が無いため）。
- dotfiles 側（`lib/Brewfile` と `lib/zshrc`）は `HEAD` の内容と比べる（`git show HEAD:<パス>`）。作業ツリーの未コミットの変更は `lib` の項目として別に出る。作業ツリーと比べると、未コミットの変更にしかない行が「dotfiles にある」と判定され、その変更を破棄したときに設定がどこにも残らなくなるため。
- サードパーティの tap のもの（`homebrew/core` と `homebrew/cask` 以外）は、`body` と `id` に完全な名前（`<user>/<tap>/<名前>`。`brew list --formula --installed-on-request --full-name` / `brew list --cask --full-name`）を出す。Brewfile に短い名前で書くと、新しい Mac の `brew bundle` が失敗するため。
- dotfiles ブロック: `cmd/common.sh` の `has_block`（`grep -qF "# >>> <名前> >>>"`）と同じ判定にし、`cmd/setup` が書く `# >>> dotfiles >>>` と `cmd/install_brew` が書く `# >>> dotfiles: homebrew >>>`（`# >>> dotfiles: <名前> >>>` の形）を含む行から、同じ名前の `# <<< <名前> <<<` を含む行まで。名前が違うもの（`# >>> dotfiles-work >>>` など）はブロックではなく、段落として項目に出る。判定は collect の 1 か所（`AWK_BLOCK`）にまとめ、`zshrc-block`、段落の分割、閉じていない場合の `warn` のどれもそこから決める。閉じていなければ開始行から最後までを除き、`warn` を出す。
- `zprofile` では、コードの部分（行末のコメントを除いた部分）に `brew shellenv` を含む段落を、段落ごと除く（dotfiles ブロック導入前に追記されたもの。arm64 と Intel で分ける `if` / `else` の一部だけを消すと、残った `eval` が無条件に走るため）。段落をつなぐかは元の内容で決め、除くのはつないだ後にする。除いた段落は、その行の範囲を `warn` に出す（ほかの設定が同じ段落にあっても項目にならないため）。行末のコメントにだけ `brew shellenv` がある行は除かない。
- `zshrc` と `zprofile` は、空行で区切った「段落」を 1 項目にする。空行には空白だけの行も含めるが、100 文字以上の空白だけの行は段落に残す（§6 の `garbage`）。dotfiles ブロックも段落の区切りになる。コメントだけの段落と空の段落は出さない。
- 段落がそれだけで構文として完結しない（`zsh -n` が通らない）ときは、通るまで次の段落とつなぐ（`if` や関数の中の空行で、`fi` や `}` だけの断片ができないようにするため）。閉じていないヒアドキュメント（`<<EOF` などの終わりの行がまだ無い）と、最後のコメントでない行の、行末のコメントを除いたコードの部分が `\`（`\\` ではない）`&&` `||` `|` で終わる段落も、`zsh -n` が通っても完結していないものとしてつなぐ（`zsh -n` はファイルの終わりでこれらを通すため）。dotfiles ブロックを越えてはつながない。ファイルの最後か dotfiles ブロックの手前までつないでも通らなければ、そこまでを 1 項目にして `warn` を出す。
- VS Code の拡張機能（Brewfile の `vscode` 行）は、VS Code を §9 で取り込むときに collect に追加する。今は扱わない。

## 5. collect の出力形式

標準出力に次のブロックを順に出す。Agent が読む前提なので、毎回同じ形式にする。

```
=== repo
branch: main
behind: 0
ahead: 0
dirty: README.md
zshrc-block: 7-9
zshrc-sources-lib: yes
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

- `=== repo`: `branch` は現在のブランチ（detached HEAD なら `HEAD`）。`behind` と `ahead` は `refs/remotes/origin/<branch>` との差のコミット数。fetch に失敗したとき、`origin/<branch>` が無いとき、detached HEAD のときは `unknown` にし、理由を `warn` に出す。`dirty` は `lib/` 以外の未コミットの変更（未追跡を含む）で、1 ファイル 1 行、無ければ行を出さない。`zshrc-block` は `~/.zshrc` の dotfiles ブロックの行の範囲（`7-9`。無ければ `none`。ブロックが複数あるときは、このリポジトリの `lib/zshrc` を source する行があるブロック、無ければ最初のブロック）。`zshrc-sources-lib` は、そのブロックの中にこのリポジトリ（同じリポジトリのどの worktree でもよい）の `lib/zshrc` を source する行があるか（`yes` / `no`）。
- `=== item`: 差分 1 件。
  - `kind`: §4 の種類。
  - `id`: 除外リスト（§7）で使う識別子。`<kind>:<識別子>` の形。`brew` `cask` `tap` は名前、`zshrc` `zprofile` は段落のコメントでない行を前後の空白を除いて ` ⏎ ` でつないだもの（1 行の段落ならその行。段落の中身が変われば別の項目として扱う）、`lib` はリポジトリからの相対パス。`secret` が立つ `zshrc` `zprofile` の項目は、秘密情報を除外リストに書き写さないよう `<kind>:sha256:<上の文字列の SHA-256>` にする（末尾に改行を付けない文字列から求める）。
  - `lines`: `zshrc` `zprofile` だけ。`id` の次の行に出す。段落がファイルの何行目から何行目か（`lines: 12-15`。1 から数える）。skill はこの範囲でローカルの段落を消す（同じ内容の段落が複数あっても取り違えないため）。
  - `direction`: `local`（ローカルにだけある）、`dotfiles`（dotfiles にだけある）、`changed`（`lib/` の未コミットの変更）のどれか。
  - `flags`: §6 のフラグを、§6 の表の順にカンマ区切りで。無ければ `-`。
  - `body:` の後: 本文。各行の先頭に 4 スペースを付ける。`brew` `cask` `tap` は名前、`zshrc` `zprofile` は段落の全文、`lib` は §5.1 の要約。`secret` が立つ項目は、秘密と判定した値を `***` に置き換える（表に載せたときにチャットや transcript に残さないため）。`lib` の diff では、足された行だけでなく、消された行と前後の文脈の行も同じ条件で置き換える（置き換えは本文のすべての行に行い、フラグの判定は足された行だけで行う。§6）。置き換えは、200 行に切る前の全文に行ってから切る。
- `=== warn`: 確認できなかったこと（1 行 1 件）。無ければブロックを出さない。段落について出す `warn` の行番号は、その項目の `lines` の開始と同じにする。項目にならなかった段落（`brew shellenv` を含むもの、除外リストで除いたものなど）には、「閉じていない」の `warn` を出さない。
- `=== summary`: `items`（出した項目数）と `ignored`（除外リストで除いた数）。
- オプション: `--no-fetch`（`git fetch` しない。`behind` と `ahead` はローカルの追跡ブランチで数える）。
- `git fetch` は固まらないように区切る。全体を 30 秒（環境変数 `COLLECT_FETCH_TIMEOUT` で変えられる）で打ち切る（macOS には `timeout` が標準で無いので、`timeout`、`gtimeout`、`perl` の `alarm` の順に使い、どれも無ければ次のオプションだけにする）。パスワードの入力は待たず（`GIT_TERMINAL_PROMPT=0`）、HTTP は転送が止まれば切る（`http.lowSpeedLimit` `http.lowSpeedTime`）。ssh は、ユーザーが `GIT_SSH_COMMAND`、`GIT_SSH`、`core.sshCommand` のどれも決めていないときだけ `GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=10'` を付ける（決めているものは、ssh 以外のコマンドかもしれず、上書きすると設定が変わるため、そのまま使い、全体の打ち切りだけで守る）。打ち切りは fetch の失敗と同じに扱う（`behind` と `ahead` は `unknown`、`warn` を出す）。
- テストのために `HOME` と `PATH` を差し替えて動くようにする（`~` は `$HOME` で解決し、brew は `PATH` から探して、無ければ `load_brew` で探す。そのため brew が標準の場所にある Mac では、brew が無い状態はテストで作れない）。除外リストの場所は環境変数 `DOTFILES_IGNORE_FILE` で差し替えられる。
- リポジトリの場所は `~/.config/dotfiles/repo` から解決する。Codex の plugin cache や移動済み clone から起動しても同じ登録先を使う。`=== repo` ブロックの `path:` に解決先を出す。
- 終了コード: 出力できたら 0。リポジトリが見つからないなど、出力できなかったら 1。

### 5.1 `lib` の要約

- `.plist`: 変わったキーのパスと、前後の値（80 文字を超える値は省略）。`HEAD` の内容と作業ツリーの内容を比べる。どちらかを plist として読めない（新規、削除、壊れている）ときは `git diff` にする。配列の要素が `Guid` キーを持つ辞書（iTerm2 のプロファイルなど）なら、位置ではなく `[Guid=<値>]` で識別する（要素の削除や並べ替えで、後ろの要素がすべて変わったように見えないため）。同じ配列で `Guid` が重なる要素は位置で識別する。本文とフラグは、plist を 1 回だけ読んだ結果から作る。
- それ以外: `git diff` の内容。未追跡のファイルは先頭 200 行。
- どれも 200 行を超えたら省略し、省略したことを書く。
- 状態を表す補助の行を先頭に付けてよい: `(未追跡のファイル)`、`(バイナリファイル)`、`(空のファイル)`、`(シンボリックリンク: …)`、`(HEAD との差分はありません)` など。
- 200 行に切るのは表示のためだけで、フラグの判定は切る前の全文（全文の diff、未追跡のファイルの全体）に対して行う（201 行目より後ろの秘密情報も見つけるため）。

### 5.2 サブモード

引数の先頭に 1 つだけ指定する。どれも読み取り専用で、書き込むのは標準出力だけ。`<出力ファイル>` は、保存した collect の出力（SKILL.md の 1 で残すもの）。`kind` と `lines` は項目のもの。引数が誤っていれば、メッセージを標準エラー出力に出して終了コード 1 にする。

| 呼び出し | 出力 | 終了コード |
|---|---|---|
| `--body <出力ファイル> <kind> <lines>` | その項目の `body`（先頭の 4 スペースを外したもの） | 見つからなければ 1 |
| `--in-worktree <出力ファイル> <kind> <lines>` | その段落のコメントでない行の並びが、作業ツリーの `lib/zshrc` のトップレベルに、同じ順で連続して現れるか（`yes` / `no`）。`in-dotfiles` と同じ関数で、`HEAD` の代わりに作業ツリー | 見つからなければ 1 |
| `--check <出力ファイル> <kind> <ファイル> <lines>...` | ファイルの各範囲の内容が、その項目の `body` と一致するか。範囲ごとに `<lines>: 一致` / `<lines>: 不一致`（中身は出さない） | 1 つでも不一致なら 1 |
| `--between <ファイル> <from> <to か end> [skip...]` | `from` 行目から `to` 行目（`end` なら最後）までのうち、`skip`（`12-13` の形の範囲）に入らないコードの行（空行と `#` で始まる行以外）の行番号（中身は出さない） | 0 |
| `--without <ファイル> <lines>...` | ファイルから各範囲の行を除いた内容。リダイレクト前提で、標準出力が端末ならエラーにする。範囲は順不同でまとめて除く（行番号がずれない）。元のファイルは書き換えない | 0 |
| `--diff <パス>...` | `lib/` のファイルの `HEAD` との差分（未追跡のファイルは中身、plist は変更の要約）。秘密と判定した値は、消された行と文脈の行を含めて `***`。行数は切らない | 0 |

- `--diff` は、SKILL.md が commit の前に差分を見せるために使う。生の `git diff` は、消された行と文脈の行の秘密の値をそのまま出す（秘密を消す変更は `secret` が立たない）ので、チャットに出さない。
- 範囲（`lines`）は `開始行-終了行`（1 から数える）。

## 6. フラグ

| フラグ | 条件 | skill のおすすめ |
|---|---|---|
| `home-path` | コードの部分（コメントの行と行末のコメントを除く）に `$HOME` の絶対パス（`/Users/<ユーザー名>/...`）を含む | 共通化。取り込むときに `$HOME` か `~` に書き換える |
| `missing-path` | コードの部分に、`~/...`、`$HOME/...`、`${HOME}/...`、`/Users/...` のパスで、存在しないものを参照している（引用符で囲んだパスと `\ ` でエスケープした空白は、パスの一部として扱う） | ローカル専用 |
| `secret` | トークンらしい文字列を含む（下の条件） | 共通化を選べない。ローカル専用か保留だけ |
| `unscanned` | `lib` だけ。中身を調べられていない: 未追跡のバイナリ、バイナリの差分（`Binary files ... differ`）、plist の `data:` の値で base64 として読めないもの。plist の `data:` は base64 を戻して、印字できる文字の並びを `secret` の条件で調べ、調べられたものには付けない（圧縮や暗号化された中身は調べられないので、既知の制限） | commit をおすすめしない（保留。理由に「中身を確かめていない」と書く）。commit は選べる |
| `garbage` | 1000 文字以上の行、または 100 文字以上の空白だけの行がある | 取り込むときにその行を消す |
| `in-dotfiles` | 段落のコメントでない行の並びが、`HEAD` の `lib/zshrc` のトップレベルに、同じ順で連続して現れる（下の「`in-dotfiles` の比べ方」） | 共通化（dotfiles にあるので、ローカルから消すだけ） |

フラグを付ける種類: `brew` `cask` `tap` には付けない。`zshrc` `zprofile` には `unscanned` 以外の 5 種。`lib` には `in-dotfiles` 以外の 5 種を、足された内容（diff の `+` 行、未追跡のファイル全体、plist の変更後の値）だけで、`body` を 200 行に切る前の全文について判定する。`secret` も同じで、消された行、前後の文脈の行、plist の変更前の値では立たない（秘密を消す変更を commit できなくしないため）。一方、`***` への置き換えは、`body` に出すすべての行（消された行、前後の文脈の行、plist の変更前の値も含む）に行う（誤って commit した秘密を消す変更でも、表やチャットに平文で出さないため）。

`lib` の項目では、`secret` があれば commit を選べない（破棄か保留だけ。おすすめは保留）。`unscanned` があれば commit は選べるが、おすすめは保留にする。ほかのフラグは理由に書くだけで、書き換えはしない。

### `in-dotfiles` の比べ方

`HEAD` の `lib/zshrc` のコメントでない行を前後の空白を除いて並べ、段落の行の並びが連続して現れる位置を探す。当たった位置が `lib/zshrc` のトップレベルにあるものだけを `in-dotfiles` とする（字下げを無視した比べ方のままだと、トップレベルの `export FOO=1` が、`lib/zshrc` の `if ...; then` の中の `  export FOO=1` に一致して、設定がどこにも残らないのに消されるため）。

- トップレベルとは、当たった範囲の最初の行より前までの内容と、当たった範囲の内容が、それぞれ単独で構文として完結していること（段落をつなぐときと同じ判定。`zsh -n` が通り、ヒアドキュメントが閉じていて、最後の行が `\` `&&` `||` `|` で終わらない）。`if` や関数やヒアドキュメントの中の行は、手前までが完結しないので当たらない。
- トップレベルの行どうしは、前後の空白を除いて比べる（字下げの違いは無視する）。字下げを無視しないことにはしなかった（トップレベルに字下げのある行を書くことがあり、構文で位置が決まるため）。
- zsh が無いときは、字下げのない行から始まる一致だけを見る。
- 作業ツリーの `lib/zshrc` との比較（`--in-worktree`。SKILL.md の「作業ツリーの `lib/zshrc` にあるか」）も、同じ関数で行う。

`secret` の条件は次のどれか:

- 変数への代入（行の中の `NAME=値` の形の単語。`export` `sudo` `env` の引数、`;` `{` `then` `if` の後なども含む。`alias` の名前と `[[ ... ]]` の中は代入ではない。`alias` の値（引用符の中）は、その中をコマンドとして同じ条件で見る（`alias deploy='HEROKU_API_KEY=... heroku deploy'`））で、変数名が `TOKEN` `SECRET` `PASSWORD` `PASSWD` `API_KEY` `APIKEY` `PRIVATE_KEY` `CREDENTIAL` を含むか、`_KEY` で終わるもの（大文字小文字は区別しない）。値が `$` か `` ` `` で始まるもの（`"$(gh auth token)"` や `` `gh auth token` `` など。ただし `${NAME:-語}` `${NAME:=語}` `${NAME-語}` `${NAME=語}` は、`語` を値として同じ条件で見る）、空の値、パス（`~` `./` `../` で始まるもの、`/` で始まり最初の要素が `/` 直下に実在するディレクトリのもの（`/opt/...`、`/Users/...`。base64 の秘密は `/` から始まりうるため）、名前が `_FILE` `_PATH` `_DIR` で終わるもの、`.txt` `.json` `.yaml` `.yml` `.toml` `.pem` `.key` `.conf` `.cfg` `.ini` `.env` `.gpg` `.asc` で終わるもの。`/` を含むだけの値は除かない。base64 の秘密は `/` を含むため）、真偽値や数値だけの値（`true` `false` `yes` `no` `0` など）は除く（`SSH_KEY=~/.ssh/id_rsa` や `TOKENIZERS_PARALLELISM=false` や `MAX_TOKENS=4096` で共通化を選べなくならないため）。ただし数値だけの値の除外は、名前が `PASSWORD` `PASSWD` `SECRET` `PIN` で終わるときは行わない（`PASSWORD=12345`。`PASSWORD_STORE_CLIP_TIME=45` は除く）。`$` の除外は、単一引用符で囲んだ値と `$'...'`（どちらも展開されない文字列）には行わない。
- 設定ファイル形式の `キー: 値`、`キー = 値`、`"キー": "値"` で、キーが上と同じ条件に当たり、値も上と同じ除外に当たらないもの（`lib` の YAML / TOML / JSON のため）。コメントの行（`#` `;` で始まる。`//` で始まる行は `.npmrc` の `//registry.npmjs.org/:_authToken=...` があるのでコメントとみなさない）、`{` か `[` で始まる値、`""` で囲んだキーに `""` で囲んでいない値が付くもの（JSON の `null` など）は見ない。キー名のハイフン（`api-key`）は条件に当たらない（既知の制限）。plist は変更後の値だけで判定し、キーの名前は見ない。
- `ghp_` `gho_` `github_pat_` `npm_` `glpat-` `AIza` `sk-` `sk_live_` `rk_live_` `xox?-` `AKIA` で始まる値、`Bearer <トークン>`（16 文字以上）、`_authToken=<値>`（8 文字以上。どちらも `$` で始まる値は除く。`.npmrc` の `_authToken=${NPM_TOKEN}` は普通の書き方のため）、`-----BEGIN ... PRIVATE KEY-----`。英数字と `_` 以外の文字の直後（`${GH_TOKEN:-ghp_...}` の `-` の後など）か行頭から始まり、ある程度の長さが続くものだけにする（`disk-` などに誤って反応しないため）。
- URL の中の認証情報（`://<ユーザー>:<パスワード>@`。パスワードが `$` で始まるものは除く）。パスワードは、次の `/` か空白か行末より手前にある最後の `@` までとする（`p@ss` のように `@` を含むパスワードの一部が残らないため）。

値が複数行にわたるとき（YAML の `キー: |` `キー: >` のブロック、閉じ引用符が後の行にある引用符の値）は、`secret` と判定した値の続きの行もすべて `***` に置き換える。

複数のフラグが立ったときは `secret` > `unscanned` > `in-dotfiles` > `missing-path` > `home-path` の順に優先する。`garbage` は、おすすめとは別に「取り込むときにその行を消す」という但し書きとして扱う。

## 7. 除外リスト

- 場所: `~/.config/dotfiles/ignore`。Mac ごとに持ち、リポジトリには入れない。
- 形式: 1 行に 1 つ、§5 の `id` をそのまま書く。空行と `#` で始まる行は無視する。行末の空白と CR は取り除いてから比べる（手で編集したときに一致しなくならないため）。
- collect は、`id` が完全に一致する `direction: local` の項目を出さず、`ignored` に数える（除外リストはローカル専用から作られるので、逆向きの差分は隠さない）。`lib:` で始まる行は無視し、`warn` を出す（`lib` の項目はローカル専用を選べない。隠すと、その未コミットの変更が取り込みの commit に混ざるため）。ファイルが無ければ除外なしとして扱う。
- skill は、ユーザーが「ローカル専用」にした項目の `id` を `${DOTFILES_IGNORE_FILE:-$HOME/.config/dotfiles/ignore}` に追記する（ディレクトリが無ければ作る。ファイルの末尾が改行で終わっていなければ、先に改行を足す）。

## 8. skill の流れ

§9 のツールの追加を頼まれたときは、1〜4 → §9 → 5 の順に行い、push の確認は最後に 1 回だけにする。

1. **開始時の確認**: `collect` を実行し、出力を一時ファイルに残す（後の手順が §5.2 のサブモードで使う）。
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
   - 取り込んだ（または `in-dotfiles` だった）段落は、ローカルの `~/.zshrc` / `~/.zprofile` から消す。取り込んだ段落を消すのは、4 でその `lib/zshrc` の commit が済んだ後にする（commit を断ったり失敗したりしたら消さない。未コミットの変更にしか設定が残らず、次回の「破棄」で失われるため）。ローカルから消すのは、4 の後（commit を飛ばしたときも）に 1 回でまとめて行う（`lines` は 1 の collect の行番号なので、同じファイルから 2 回に分けて消すと後の回の行番号がずれるため）。`in-dotfiles` の段落はリポジトリを変えないので、commit の有無にかかわらず消す。ただし `zshrc-sources-lib` が `yes` でなければ消さない（`lib/zshrc` が読み込まれていないので、設定が効かなくなる。`cmd/setup` の実行を勧める）。消すと、その段落は dotfiles ブロックの位置（`zshrc-block`）で実行されるようになる。段落の元の位置とブロックの位置の間で実行される、残るコードの行（`--between` で行番号だけを出して確かめる。中身は出さない）があるとき（`~/.zshrc` ではブロックの前後どちらの段落も、段落とブロックの間の行。`~/.zprofile` の段落は、`~/.zprofile` でその段落より後ろの行と、`~/.zshrc` でブロックより前の行。この回に消す段落の行は数えない）は、実行順が変わることを見せて AskUserQuestion で消すかを確認する。おすすめは、間の行が段落の設定するものを使わず同じものを設定してもいないと Claude が判断できれば「消す」（消さないと同じ設定が 2 回実行されたまま残る）、依存しているか分からなければ「消さない」（`compinit` より後に `compdef` が走らなくなるなど）。中身を見られない行（表に出ていない行のうち、ほかの dotfiles ブロックと `brew shellenv` の段落以外）があれば「消さない」。`in-dotfiles` の段落は、作業ツリーの `lib/zshrc` にもその段落があるとき（`--in-worktree` が `yes`）だけ消す（この回に commit する変更がその行を消していると、設定がどこにも残らないため）。消す範囲は `lines` で決め、その範囲の内容が `body` と一致することを `--check` で確かめてから消す（一致しなければ流れ全体を止める。ファイルが変わっているため）。比べる `body` は、1 で一時ファイルに残した collect の出力から `kind` と `lines` で取り出される。段落を除いた内容は `--without`（範囲をまとめて渡し、一時ファイルにリダイレクトする）で作る。消す前に差分を `diff -U0` で見せて確認し（前後の行に、除外した秘密の段落が出ないようにするため）、`<ファイル>.backup-YYYYmmddHHMMSS` に退避する。書き換える前に、書き換え後の内容を `zsh -n` で確かめ、通らなければ書き換えずに流れ全体を止め（残りのファイルと push に進まない。commit と除外リストへの追記は済んでいる）、ユーザーの指示を待つ（先に済んだファイルの書き換えは退避ごと残る）。
   - `lib` の「破棄」は `git restore --source=HEAD --staged --worktree`（stage した変更も戻すため。未追跡なら削除）。iTerm2 の plist は、iTerm2 が起動中だと終了時に書き戻されることを伝える。
   - 「ローカル専用」は除外リストに追記する。「保留」は何もしない（次回また出る）。
4. **commit**: commit するかは、3 でリポジトリのファイルを変えたか（取り込み、dotfiles から削除、`lib` の commit）で決める。保留にした `lib` の変更は残るので、`git status` が空かどうかでは決めない。変えたものが無ければ commit を飛ばし、3 のローカルからの削除を行ってから 5 に進む。commit は `git commit -- <パス>` でそのエリアのファイルだけにする（ほかに stage されているものを含めないため）。差分を `collect --diff`（秘密と判定した値を `***` にする。生の `git diff` は、秘密を消す変更で消される値をチャットに出すため使わない）で見せて確認してから、エリアごとに分けて `main` に直接 commit する（個人用の dotfiles なのでブランチや PR は作らない）。メッセージは `[feat]` `[fix]` `[del]` + 日本語（例: `[feat] Brewfile に actionlint などを追加`）。
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

- dotfiles リポジトリで Agent を起動し、Claude Code では `/nozimin:sync-to-dotfiles`、Codex CLI では `/skills` の一覧から `$nozimin:sync-to-dotfiles` を選ぶ。ツールを管理に加えたいときは引数で伝える。
- 除外リストの場所（`~/.config/dotfiles/ignore`）と形式。
- 新しいツールを追加した後は `cmd/setup` を実行し直す。

「構成」に `lib/agents/nozimin/skills/sync-to-dotfiles/` を足す。

## 10.1 既知の制限

- 段落が閉じないまま続くと、つなぐたびに、伸びていく全文に `zsh -n` をかけ直すので、処理時間が段落の数の 2 乗で増える。1 回の検査は `zsh -n` 1 回で、2 回目（閉じていないヒアドキュメントの確認）は `<<`（`<<<` のヒアストリングを除く）を含むときだけにしてある。判定の結果は変えていない。`~/.zshrc` の大きさでは問題にならない。
- 設定ファイル形式の `secret` は、キー名のハイフン（`api-key`）に当たらない。
- 段落を消した後、前後の空行が重なって残る。内容には影響しない。
- 実行順の確認は `~/.zshrc` / `~/.zprofile` の行だけを見る。`lib/zshrc` の中で、足す位置（末尾）より前にある行との順序の変化（`compinit` より後に `fpath` が足されるなど）は見ない。
- 項目ごとのプロセスは、`secret` `home-path` `garbage` の判定と `***` への置き換えを 1 回の `awk` にまとめ、`missing-path` はパスを含みうる行があるときだけ `grep` を 1 回足す形にして減らしてある（段落 1 つで `zsh -n` と `awk` が数回）。それでも、段落が数百あると 1〜2 秒かかる。
- 秘密らしい名前の URL（`OAUTH_TOKEN_URL=https://...`）も `secret` になり、共通化を選べない。Slack の Webhook のように URL そのものが秘密のこともあるので、安全側に倒している。
- plist の `data:` は、base64 を戻した中身の印字できる文字の並びだけを調べる。圧縮や暗号化された中身は見えないが、`unscanned` は付かない（base64 として読めないものだけに付く）。
- `lib` の diff の `secret` は、足された行だけで判定するが、`-` の行と `+` の行が交互に並ぶ複数行の値（閉じ引用符が後の行にあるもの）では、`-` の行から続く状態を `+` の行が引き継ぐことがある（余分に `secret` が立つ側に倒れる）。
- fetch を打ち切っても、`ssh` の子プロセスは `ConnectTimeout`（ユーザーが `GIT_SSH_COMMAND` などを決めているときは、その設定）に従って終わるまで残ることがある。
- `zshrc-sources-lib` は同じリポジトリのどの worktree の `lib/zshrc` でも `yes` になる。`~/.zshrc` が main 以外の worktree を読み込んでいると、main への commit がその worktree に入るまで、取り込んだ設定が効かない。

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
5. SKILL.md が §3、§8、§9 をすべて手順として含み、§5 の形式を前提に書かれている。`awk` / `sed` を手で書く手順は無く、§5.2 のサブモードを呼ぶ。
6. README に §10 の内容がある。
7. 一時的な `HOME` とテスト用の clone で、次が期待どおりになる: (a) `lib/zshrc` の 201 行目より後ろの `export GITHUB_TOKEN=...` に `secret` が立つ。(b) 秘密を消す変更に `secret` が立たず、`body` の消された行は `***` になる。(c) 未追跡のバイナリ、バイナリの差分、plist の `data:` の秘密に `unscanned` か `secret` が立つ。(d) トップレベルの行が `lib/zshrc` の `if` の中の同じ行で `in-dotfiles` にならない。(e) `# >>> dotfiles-work >>>` は段落として出て、`# >>> dotfiles: homebrew >>>` はブロックになる。(f) 固まる origin でも `collect` が `COLLECT_FETCH_TIMEOUT` 秒で終わる。(g) サブモード（§5.2）が、秘密を含みうるファイルの中身を標準出力に出さない（`--without` はリダイレクトを要求する）。
