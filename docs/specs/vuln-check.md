# vuln-check 仕様

この Mac に入っているアプリやライブラリのうち、脆弱性のあるものを一覧にする Claude Code の skill。
この文書が実装の正であり、実装との食い違いは実装側を直す（仕様を変えるときはこの文書を先に直す）。

## 1. 目的と前提

- 手動実行専用。`/vuln-check` と打ったときだけ動く（`disable-model-invocation: true`）。
- **読み取り専用**。パッケージやアプリ、brew のメタデータを一切変更しない（`brew update` / `brew upgrade` も実行しない）。更新コマンドは提示までで、実行はユーザーが行う。
- 出力は日本語。
- **役割分担**: バージョン比較はすべて決定的な処理（API とスクリプト）で行う。AI は名前の対応付け、修正版の抽出、トリアージ、文章化を担う。AI が抽出した修正版とインストール済みバージョンの比較も、スクリプトの `compare` で行う。

## 2. ファイル構成

```
lib/claude/skills/vuln-check/
  SKILL.md              手順・トリアージ基準・レポートの雛形
  scripts/vulncheck     決定的な処理（収集・照合・バージョン比較）。bash
  tests/run             試験（§10）
docs/specs/vuln-check.md  この文書
lib/claude-code.md        skill のリンクと /vuln-check の使い方
                          （lib/claude.md にしない。大文字小文字を区別しない FS では lib/CLAUDE.md として自動で読み込まれる）
```

- `cmd/setup` の `setup_claude_skills` が `lib/claude/skills/*/` を skill ごとに `~/.claude/skills/<名前>` へシンボリックリンクする（§11）。
- `scripts/vulncheck` は bash で書き、shellcheck を警告なしで通す。依存は OS 付属のもの（`bash` `curl` `jq` `xmllint` `PlistBuddy` `sort -V` など）と、インベントリ対象のツール自身（`brew` `npm` など）だけ。Python は使わない。

## 3. `scripts/vulncheck` の共通仕様

### 3.1 出力の形（エンベロープ）

各サブコマンドは標準出力に **エンベロープの JSON 配列** を 1 つ出す（`compare` を除く）。エンベロープは 1 つの取得元（ソース）に対応する。

```json
{
  "source": "kev",
  "layer": "inventory | layer1 | layer2",
  "status": "ok | warn | error",
  "count": 0,
  "fetched_at": "2026-11-09T15:30:00+09:00",
  "evidence": { "url": "...", "total": 1523 },
  "notes": ["人が読む補足"],
  "items": []
}
```

- `status` は**取得元（ソース）そのもの**の状態を表す。
  - `ok`: 取得でき、件数や鮮度も妥当。
  - `warn`（要確認）: 取得はできたが、件数 0、鮮度切れ、一部の取得の失敗、照合に使うインベントリの欠けなど、ソースの結果を信用しきれない。
  - `error`（取得失敗）: コマンドの失敗、HTTP エラー、タイムアウト、解析の失敗。
- **項目ごとの要確認**: バージョン不明、対応付けできない（`unmapped`）、比較不能など、ソースは正常だが個々の項目を判定できないものは、エンベロープの `status` を変えず、その項目に `"review": "<理由>"` を付ける（判定できる項目は `"review": null`）。エンベロープの `evidence.review` にその件数を書く。
- `count` は `items` の件数ではなく、**そのソースで実際に読み取った件数**（例: KEV のカタログ全件数、インベントリの件数）。`items` は照合候補などに絞り込んだ後の中身でよい。絞り込んだ場合は `evidence` に前後の件数を書く。
- `evidence` には「該当なし」の根拠になる情報（読んだ URL、件数、読み取った最新版、取得できた日付範囲など）を入れる。
- 1 つのソースが失敗しても他のソースの処理は続け、失敗したソースは `status: "error"` のエンベロープとして出す。スクリプトの終了コードは、エンベロープを出力できれば 0、引数の誤りなどで出力自体ができなければ非 0。

### 3.2 silent failure を防ぐ作法

- `set -euo pipefail` を使う。`curl` は `-fsS --max-time` 付きで呼ぶ。
- 取得や解析が失敗したとき、空の結果を「該当なし」として出さない。必ず `error` か `warn` にする。
- 件数 0 は、0 件が正常であり得るソース（例: VS Code の削除済み拡張との一致）を除き `warn` にする。0 件が正常かどうかは「読み取った件数」（`count`）で判断する。例: 削除済み一覧を 0 件しか読めなければ `warn`。

### 3.3 取得元の差し替え（試験用）

すべての外部 URL を環境変数で差し替えられる。`file://` も受け付ける。

| 環境変数 | 既定の取得元 |
|---|---|
| `VULNCHECK_OSV_URL` | `https://api.osv.dev`（`/v1/querybatch` と `/v1/vulns/<id>`） |
| `VULNCHECK_BREW_FORMULA_URL` | `https://formulae.brew.sh/api/formula`（`/<name>.json`） |
| `VULNCHECK_BREW_CASK_URL` | `https://formulae.brew.sh/api/cask.json` |
| `VULNCHECK_ITUNES_URL` | `https://itunes.apple.com/lookup` |
| `VULNCHECK_EOL_URL` | `https://endoflife.date/api` |
| `VULNCHECK_KEV_URL` | `https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json` |
| `VULNCHECK_JVN_IPEDIA_URL` | `https://jvndb.jvn.jp/ja/rss/jvndb_new.rdf` |
| `VULNCHECK_JVN_URL` | `https://jvn.jp/rss/jvn.rdf` |
| `VULNCHECK_JPCERT_URL` | `https://www.jpcert.or.jp/rss/jpcert.rdf` |
| `VULNCHECK_VSCODE_REMOVED_URL` | `https://raw.githubusercontent.com/microsoft/vsmarketplace/main/RemovedPackages.md` |

`VULNCHECK_NOW`（ISO 8601）で「現在時刻」を差し替えられる（層1の鮮度の判定の試験用）。

### 3.4 サブコマンド

| サブコマンド | 層 | 内容 |
|---|---|---|
| `inventory` | inventory | インベントリを集める（§4） |
| `osv [--inventory FILE]` | layer2 | 言語パッケージを OSV で照合（§5.1） |
| `latest [--inventory FILE]` | layer2 | brew・アプリ・OS・ランタイムの最新版と比較（§5.2） |
| `vscode [--inventory FILE]` | layer2 | VS Code 拡張を削除済み一覧と照合（§5.3） |
| `kev [--inventory FILE]` | layer1 | KEV 全件から照合候補を出す（§6） |
| `jvn [--inventory FILE]` | layer1 | JVN iPedia と JVN の RSS が持っている範囲（§6） |
| `jpcert` | layer1 | JPCERT/CC 注意喚起の RSS が持っている範囲（§6） |
| `compare A B` | - | バージョン比較。`A<B` なら `lt`、等しければ `eq`、`A>B` なら `gt` を出す（§7） |
| `all [--save]` | - | `inventory` を実行し、その結果を使って他のすべてを実行し、全エンベロープを 1 つの配列で出す。`--save` を付けると、新しく作った一時ディレクトリのファイルに書き、標準出力にはそのパスだけを出す（skill がシェルのリダイレクトを使わずに済むようにする） |

`--inventory FILE` を省略したときは、その場で `inventory` を実行する。`FILE` は `inventory` の出力（エンベロープ配列）と同じ形。

## 4. インベントリ

各項目の形: `{"kind", "name", "version", "origin", "bundle_id", "path"}`（該当しないものは `null`）。`kind` ごとに 1 つのエンベロープを出す。

| kind | 取得方法 | 備考 |
|---|---|---|
| `brew-formula` | brew（ローカル情報のみ。`HOMEBREW_NO_AUTO_UPDATE=1`） | revision（`_1` など）も保持する |
| `brew-cask` | brew | **.app を持たない cask だけ**（例: `claude-code`）。.app を持つ cask は `app` 側で扱う。フォントは除外 |
| `app` | `/Applications/*.app` の Info.plist の `CFBundleShortVersionString` のみ（`CFBundleVersion` はビルド番号のことが多いので使わない） | brew の記録したバージョンは使わない。`origin` は `appstore`（`Contents/_MASReceipt` あり）/ `brew-cask` / `sparkle`（`SUFeedURL` あり）/ `other`。Safari は `macos` 側で扱う |
| `npm` / `pnpm` | `npm ls -g --json --depth=0` / `pnpm ls -g --json` | ecosystem は npm |
| `uv` | `uv tool list` | ecosystem は PyPI |
| `gem` | rbenv の各 Ruby で `gem list` | ecosystem は RubyGems。インストール済みの版ごとに 1 項目（OSV の照合に正確な版が要る） |
| `macos` | `sw_vers`、Safari の Info.plist | macOS 本体と Safari（`name: "Safari"`）の 2 項目 |
| `ruby` | `rbenv versions --bare` | Ruby 本体 |
| `vscode` | `code --list-extensions --show-versions` | |

- ツールが入っていない kind（例: `pnpm` が無い）は `warn` ではなく `ok` + `count: 0` + `notes` に「未インストール」と書く。
- 0 件の扱い:
  - `npm` / `pnpm` / `uv` / `vscode` / `brew-cask` / `ruby` は、0 件が正常であり得る。ツールの出力を正常に解析でき、その出力自体が 0 件を示している（例: `uv tool list` の `No tools installed`、`pnpm ls -g --json` が依存なしの正しい JSON）ときは `ok` にし、`evidence` にその根拠（出力の要点）を書く。
  - `brew-formula` / `app` / `macos` / `gem` は 0 件なら `warn`（この Mac で 0 件はあり得ず、取得の失敗を疑う）。
  - どの kind でも、コマンドの失敗や解析の失敗は `error`。
- バージョンを読めない項目（例: Steam）は項目を残し `version: null` にし、§3.1 の項目ごとの要確認（`review`）にする（参考になる値があれば理由に添える。例: Steam の `CFBundleVersion`）。エンベロープの `status` は変えない。
- `origin` の値: `brew-formula` / `brew-cask` は tap、`gem` は `rbenv <版>`、`ruby` は `rbenv`、`app` は上表、それ以外は `null`。
- インベントリのエンベロープの `source` は kind 名。層2の `vscode` と同名になるので、エンベロープは `layer` と `source` の組で区別する。

## 5. 層2（全件照合）

### 5.1 言語パッケージ（`osv`）

- `npm` / `pnpm` / `uv` / `gem` の全件を OSV の `/v1/querybatch` に問い合わせる。影響範囲の判定は OSV のサーバー側に任せる。
- 該当した脆弱性は `/v1/vulns/<id>` で詳細を取り、項目に `id`、`aliases`（CVE）、`summary`、`severity`（CVSS のスコアとベクター）、`fixed`（修正版）を入れる。

### 5.2 brew・アプリ・OS・ランタイム（`latest`）

最新版を決定的に取り、インストール済みバージョンと `compare` で比べる。項目の形: `{"kind", "name", "installed", "latest", "outdated", "method", "eol", "update_command"}`。

| 対象 | 最新版の取得元 | `method` |
|---|---|---|
| `brew-formula` | formulae.brew.sh の formula API（ローカルの brew キャッシュは使わない） | `brew-api` |
| `brew-cask`（.app なし） | formulae.brew.sh の cask API | `cask-api` |
| `app`（`origin: appstore`） | iTunes Lookup API（bundle id で引く） | `itunes` |
| `app`（それ以外） | cask API で .app 名から cask を対応付ける（brew で入れたかは問わない） | `cask-api` |
| `macos` | `softwareupdate --list` | `softwareupdate` |
| `ruby` | endoflife.date（同じサイクルの最新パッチと EOL） | `endoflife` |

- エンベロープは取得元ごとに出し、`source` は `method` と同じ名前（`brew-api` / `cask-api` / `itunes` / `softwareupdate` / `endoflife`）。`count` は取得元から読み取った件数（formula の JSON の数、cask の全件数、iTunes の結果の件数、softwareupdate の更新の件数、endoflife のサイクルの数）、照合した件数は `evidence.checked`。
- `macos` は `compare` を使わず、`softwareupdate --list` に出ていれば `outdated: true` とする（`27.2 (a)` のような Rapid Security Response は `compare` では区別できないため）。
- 対応付けできなかった項目は `method: "unmapped"`、`latest: null` として出し、§3.1 の項目ごとの要確認（`review`）にする。バージョン不明や比較不能の項目も同じ。エンベロープの `status` は変えない。AI がベンダーのページで最新版を調べる（§8.2）。
- `update_command` は分かる範囲で入れる（例: `brew upgrade <formula>`、`brew upgrade --cask <cask>`、App Store、アプリ内の更新、`softwareupdate`）。

### 5.3 VS Code 拡張（`vscode`）

- 削除済み一覧（Markdown の表）を読み、インストール済みの拡張 ID と大文字小文字を区別せずに照合する。
- 項目の形: `{"id", "version", "removal_date", "type"}`。`count` は一覧から読み取った件数。一致 0 件は正常（`ok`）。

## 6. 層1（公開収集）

| ソース | 範囲 | 出すもの |
|---|---|---|
| KEV | カタログ全件 | インベントリの名前と緩く一致する候補（下記）。`evidence.total` に全件数 |
| JVN iPedia（新着 RSS）、JVN（RSS） | RSS が持っている範囲（iPedia は約 500 件で 1〜2 日分、JVN は約 20 件で 10 日前後） | 同上。`notes` に「更新分は未確認」と「RSS が持っている範囲だけを照合」 |
| JPCERT/CC 注意喚起（RSS） | RSS が持っている範囲 | 注意喚起の全件（件数が少ないため）。Weekly Report は除く |

- **候補の絞り込み**: 文脈を節約するため、スクリプトで緩い名前一致（英数字のトークンに分けて小文字化し、製品名トークンとインベントリ名トークンが重なるか）で候補に絞る。取りこぼしより拾い過ぎを優先する。最終的な対応付けは AI が行う。
- **取得範囲**: 30 日分などの固定の範囲は求めない（JVN の RSS は 30 日分を持たず、年ごとの一括ファイルは 97MB あり毎回は取得できないため）。取得できた期間（最も古い項目と最も新しい項目の日付）を `evidence.period` に必ず書き、レポートの健全性の表に出す。範囲の外の脆弱性も、インストール済みのものは層2の全件照合で拾う。
- **鮮度の確認**: ソースが更新を止めていないかを確かめる。最も新しい日付が `VULNCHECK_NOW`（既定は現在時刻）より 14 日以上前なら `warn` にする。見る日付: KEV はカタログの `dateReleased`、JVN iPedia と JVN は項目の日付の最大、JPCERT/CC は Weekly Report を含む RSS 全体の項目の日付の最大。

## 7. バージョン比較（`compare`）

- 先頭の数字部分で比べる（例: `5.10.2 GM (b5299, …)` は `5.10.2`）。先頭の `v` は無視する。数字に挟まれた `-` と `_` は区切りとして扱う（brew の revision `77.1_1`、日付の `2026-10-20`）。各要素の先頭の 0 と末尾の `.0` は無視する（`1.0 eq 1.0.0`）。
- 比較は `sort -V` を使う。
- **プレリリース**: 数字部分の直後に `-` と英字が続くもの（`1.2.3-beta`、`2.0.0-rc.1`）はプレリリースとする。数字部分が等しく片方だけがプレリリースなら、プレリリースの側を小さいとする（`1.2.3-beta lt 1.2.3`）。両方がプレリリースで接尾辞が異なるときは比較不能（終了コード 2）。プレリリースを無視して `eq` にすると、修正前のプレリリース版を「修正済み」と誤判定するため。
- 数字として解釈できない場合は終了コード 2 で失敗する（呼び出し側は「比較不能」として扱い、要確認にする）。

## 8. skill の手順（SKILL.md）

### 8.1 起動と許可

- frontmatter: `disable-model-invocation: true`。`allowed-tools` で次を事前に許可する。
  - `~/.claude/skills/vuln-check/scripts/vulncheck` の実行
  - `jq` の実行（`all --save` の出力を読む。`jq` は組み込みの読み取り専用コマンドに入っていない）
  - `WebFetch`、`WebSearch`
  - `~/Documents/vuln-check/` 以下の読み書き（レポートの保存と前回 JSON の読み込み）
- シェルのリダイレクト（`>`）で書き出さない（行き先ごとに書き込みの許可が要る）。`all` の出力は `--save` で保存する。

### 8.2 流れ

1. `vulncheck all --save` を実行して全エンベロープを保存する。出力は数百 KB になるので、表示されたパスのファイルを `jq` で `layer` と `source` ごと、照合した対象ごとに必要な部分だけを読む。
2. **層2の脆弱性の確定**
   - `osv` の項目はそのまま指摘にする。
   - `latest` で `outdated: true` の項目は、**全件**、AI がインストール済みと最新版の間のセキュリティ修正をリリースノートや NVD、ベンダーのアドバイザリで調べる。CVE と修正版を抽出し、`vulncheck compare` で「インストール済み < 修正版」を確かめたものだけを指摘にする。セキュリティ修正が見つからないものは「参考」に回す。
     - 「セキュリティ修正」は、ベンダーがセキュリティの修正と明記しているか、CVE かアドバイザリ ID が付いているもの。それ以外の修正（例: 境界外書き込みの修正とだけ書かれたもの）は「参考」の補足に書く。
     - macOS 以外（Windows、Android、iOS、Linux）だけに当たる修正は除く。インストールしたものに当たらない修正（Python 版だけの修正、ソースを配布する側の手順の問題など）も除く。
     - **影響範囲の下限**: 影響を受ける版に下限があれば（例: 4.46.0 だけ、4.51.0 から）、「インストール済み ≥ 下限」も `compare` で確かめる。下限の記載が無ければ、修正版より前はすべて影響を受けるとみなす。
     - ランタイム本体（Ruby など）は、インストール済みから最新版までの各リリースノートにある CVE を指摘にする（同梱の gem の修正も含む）。
     - NVD の画面は WebFetch で中身を読めないので、CVE の詳細は NVD API（`services.nvd.nist.gov/rest/json/cves/2.0?cveId=…`）か CVE API（`cveawg.mitre.org/api/cve/…`）で読む。
   - `review` の付いた項目（`unmapped`、バージョン不明、比較不能）は、AI がベンダーのページで最新版を調べる。読めたら、その URL とバージョンを根拠に「AI 確認」とし、判定は他の項目と同じに行う。後継のアプリに置き換わって更新が止まっている（例: 旧版の Keynote 14.5）と分かったものは EOL として扱う。どうしても判定できないものだけを「個別に要確認」とする。
   - `vscode` の一致は指摘にする。
   - EOL（`latest` の `eol` が過去の日付、または更新が止まったもの）は指摘にする。修正版は「サポート中のサイクルの最新版」（後継アプリならその名前）。
3. **層1の照合**: KEV、JVN、JPCERT/CC の候補をインベントリと AI が対応付ける。影響バージョンや修正版を抽出し、`compare` で該当を確かめる。
   - 候補は拾い過ぎ側に倒してあるので（KEV だけで百件以上になる）、まず名前の誤一致（例: LINE と Jenkins Command Line Interface）を落とし、対象ごとにまとめる。
   - KEV は修正版を持たないので、対象ごとに次のように絞ってから調べる。累積的に修正される製品（Chrome、macOS など）は、層2で最新版（`outdated: false`）なら、修正が出ている KEV は修正済みとみなし、`date_added` が直近 30 日の項目だけ「まだ修正が出ていないか」を確かめる。古い版（`outdated: true`）なら、`date_added` が新しい順に修正版を調べ、インストール済みの版がその修正を含むところまで確かめれば、それより古い項目は修正済みとみなす。複数の系列を並行して保守する製品（Rails など）は系列ごとに確かめる。
   - macOS 以外だけに当たる候補（Android、iOS だけ、Windows のインストーラだけなど）は除く。
   - 対象に当たるか決めきれない候補は「個別に要確認」とし、調べた URL を根拠に書く。
4. **クロスチェック**: 層1で該当したのに層2で検出されていないものは「層2未検出」として警告する。
5. **トリアージ**（§9）と、放置すると何が起きるかの一文（§9.2）を付ける。
6. **差分のタグ**: `~/Documents/vuln-check/reports/` の最新の `.json` と比べ、各指摘に `[新規]` / `[継続]` を、前回あって今回ないものに `[解消]` を付ける。前回が無ければ（レポートのディレクトリが無い、または `.json` が 1 つも無い）すべて `[新規]`。
   - **指摘**は「対象 × 脆弱性」の 1 組。**対象**は kind + name（例: `app Google Chrome`）。
   - 指摘の ID は次の順で決める: OSV の項目は OSV の `id`（GHSA など。CVE は後から `aliases` に増えることがあるため）。AI が見つけたものは CVE、無ければアドバイザリ ID、それも無ければ `fix:<修正版>`。EOL は `eol:<サイクルか名前>`。マルウェアは `removed:<拡張 ID>`。
   - `key` は「対象 + 指摘の ID」。`key` が違っても、同じ対象で `ids`（ID と別名の集合）が重なれば同じ指摘とみなす。
   - 同じ脆弱性をまとめるのは、同じ対象の中だけ（Ruby 本体と gem の zlib が同じ CVE でも別の指摘）。
7. **保存と出力**: レポートを保存し（§10.2）、チャットにサマリーを出す（§10.1）。

## 9. トリアージ

### 9.1 優先度

| 優先度 | 条件 | 対応の目安 |
|---|---|---|
| P0 | KEV に掲載、実際の悪用の報告あり、または VS Code 拡張が Malware として削除されている | 今日中 |
| P1 | CVSS 9.0 以上、または信頼できない入力を扱うアプリでリモートから攻撃できる | 今週中 |
| P2 | 上記以外（CVSS 7.0 以上、EOL、それ未満、ローカルからのみ攻撃可能、Malware 以外の種別で削除された拡張） | 次に更新するとき |

- KEV、CVSS、EOL、削除種別は取得したデータでそのまま判定する。
- CVSS のスコアは次の順で探す: (1) 取得したデータにある同じ CVE のスコア（`osv` の `severity`、JVN の `cvss`）の最大、(2) GHSA の重大度（`rating`）で代える（`CRITICAL` は 9.0 以上、`HIGH` は 7.0 以上として扱う）、(3) AI が NVD API / CVE API でスコアを確かめ、確かめた URL を根拠に書く。出どころによってスコアが大きく違うことがあるので（例: osv 9.8、CVE の記録 1.7）、(1) は最大を採る。CVE の記録の製品名が対象と違っても（例: Ruby が直した Onigmo の CVE が GitLab の製品として登録されている）同じ CVE のスコアを使い、そのことを根拠に書く。
- スコアを調べるのは優先度を決めるためなので、対象ごとに重大そうなものから調べ、その対象の優先度が決まったら（例: 9.0 以上が 1 件見つかり P1 に決まった）残りのスコアは調べなくてよい。調べなかった指摘は根拠に「スコア未確認」と書く。どこにもスコアが無いものは「CVSS なし」と書き、他の条件に当たらなければ P2。
- 「信頼できない入力を扱うアプリ」（ブラウザ、チャット、メール、PDF、メディア、Docker など）に当たるかは AI が判断し、理由をレポートに書く。言語パッケージ（gem、npm など）はどのアプリが使うか分からないので、この条件を当てず CVSS で判定する。
- 対象の優先度は、その対象の指摘のうち最も高いもの。
- EPSS は使わない。

### 9.2 放置すると何が起きるか

- 形式: 「〈きっかけ〉だけで、〈起きること〉」+ 感嘆符。
- 一文は**対象ごとに 1 つ**書き、その対象の指摘で共有する（Chrome のように 1 つの対象に百件以上の指摘があるため）。内容はその対象で最も優先度の高い指摘に基づく。
- 感嘆符の数は優先度で決める: P0 は `！！！`、P1 は `！！`、P2 は `！`。
- アドバイザリの内容を超えて書かない。影響の種類ごとの書き方:
  - リモートからのコード実行 →「PC を乗っ取られる」
  - 情報漏えい →「〜が抜き取られる」
  - 権限昇格 →「管理者権限を奪われる」
  - DoS →「アプリを落とされる」
  - 詳細が非公開 →「詳細は非公開。最悪の場合〜」
- 例:「細工された Web ページを開くだけで、PC を乗っ取られる！！！」

## 10. 出力

### 10.1 チャットのサマリー

```
【P0】1件 【P1】1件 【P2】4件 ／ ⚠ソース異常 1件 ／ 要確認 1件

P0 [新規] Google Chrome 156.0.8078.81 → 156.0.8079.12
  細工された Web ページを開くだけで、PC を乗っ取られる！！！
  → Chrome を再起動して更新
P1 [継続] activestorage 7.2.1 → 7.2.3.2, 8.0.2 → 8.0.5.1
  細工された画像を変換させるだけで、PC を乗っ取られる！！
  → gem update activestorage
…（P2 は件数と対象名だけ）
[解消] 2件 ／ ⚠ JVN iPedia: 取得失敗 ／ 要確認: Steam（バージョン不明）

レポート: ~/Documents/vuln-check/reports/20261109153000.md
```

- 件数は**対象の数**（指摘の数ではない）。`[解消]` の件数も対象の数。
- 修正版が系列ごとに違う対象は、`7.2.1 → 7.2.3.2, 8.0.2 → 8.0.5.1` のように版ごとに書く。

見出し（1 行目）は次の 3 種類のどれか。「個別に要確認」が 1 件以上あれば、どれにも `／ 要確認 M件` を付け足す。

| 状態 | 見出し |
|---|---|
| 指摘あり | 優先度ごとの件数。ソース異常があれば `／ ⚠ソース異常 N件` を併記 |
| 指摘なし・ソース異常あり | `⚠ソース異常あり：N件。該当なし` |
| 指摘なし・全ソース正常 | `該当なし（全ソース正常）` |

- **ソース異常**（N）は、`status` が `warn` か `error` のエンベロープの数。取得元そのものの異常だけを数える。
- **個別に要確認**（M）は、`review` の付いた項目や層1の候補のうち、AI が調べても判定できなかった**対象の数**（Steam のバージョン不明など）。AI がベンダーのページで確かめられたもの（AI 確認）は数えない。

### 10.2 レポート

- 保存先: `~/Documents/vuln-check/reports/YYYYMMDDhhmmss.md` と、同じ名前の `.json`。ディレクトリが無ければ作る。古いレポートは削除しない。
- `.md` の節:
  1. サマリー（§10.1 の見出しと件数）
  2. 指摘の一覧（優先度順）。各指摘に: 優先度、差分タグ、対象、現在のバージョン → 修正版、CVE、放置すると何が起きるかの一文、判定の根拠（KEV / CVSS / AI の判断理由）、更新コマンド
  3. [解消] の一覧
  4. 参考: 新しいバージョンはあるが、セキュリティ修正は見つからなかったもの
  5. ソース健全性
     - 表（層1、層2、インベントリ）。列: ソース、状態（OK / 要確認 / 取得失敗）、読み取った件数、根拠（層1は取得できた期間と最新の日付）、補足。「層2未検出」の警告もここに書く
     - 個別に要確認: 対象、理由、調べた URL
     - AI 確認: 対象、確かめたバージョン、読んだ URL
  6. 未チェック範囲: プロジェクトの依存関係、Docker イメージ、Claude Code のプラグインと MCP サーバー、pip の user パッケージ
- `.json` は次回の差分判定に使う。少なくとも各指摘の `key`（§8.2 の 6 の同一性）、`priority`、`tag`、`target`、`installed`、`fixed`、`ids`、`line`（放置すると何が起きるかの一文）、`rationale`、`update_command` と、ソース健全性の一覧、個別に要確認と AI 確認の一覧を持つ。

## 11. セットアップとドキュメント

- `cmd/setup` に `setup_claude_skills` を追加する。
  - `lib/claude/skills/*/` を順に処理し、`~/.claude/skills/<名前>` をそのディレクトリへのシンボリックリンクにする（ディレクトリ全体はリンクしない。既存の他の skill を壊さない）。
  - 既存の `cmd/common.sh` の関数（`link_file` など）と、README の「ツールを追加する」の約束事に従う: 済んでいれば `ok` を出して何もしない。同じ名前の実体があれば内容を見せて確認してから `~/.claude/skills-backup/<名前>.backup-<日時>` に退避する（`~/.claude/skills` の中に退避すると、退避したものも skill として読み込まれる）。古い場所を指すリンクは確認してから張り直す。
- README: セットアップ手順の表に「Claude skills」の行を足し、構成の節に `lib/claude/` と `docs/specs/` を足す。
- `lib/claude-code.md`: skill のリンクの仕組み、`/vuln-check` の使い方、対象と対象外、レポートの保存先、外部に送る情報:
  - OSV.dev: 言語パッケージの名前とバージョン
  - formulae.brew.sh: formula 名（URL に入る）
  - iTunes Lookup: App Store のアプリの bundle id
  - WebSearch / WebFetch: AI がリリースノートなどを調べるときの、アプリ名とバージョン
  - Claude（Anthropic）: インベントリとスクリプトの出力は、Claude との会話の内容として送られる

## 12. 試験（`tests/run`）

1. shellcheck: `scripts/vulncheck` と `tests/run` が警告なしで通る。
2. 故障注入: 各外部ソースについて、存在しない URL に向けると `status: "error"`、空のファイル（`file://`）に向けると `status: "warn"` になる。ベース URL のソース（OSV、formula、endoflife）は、読むパス（`v1/querybatch`、`<formula>.json`、`ruby.json` など）に空のファイルを置いたディレクトリに向ける。`softwareupdate` は URL ではないので、偽のコマンドを `PATH` の先頭に置いて確かめる。
3. 既知の陽性: インベントリを差し替え、npm の `lodash@4.17.15` を入れると `osv` が脆弱性を返す。
4. `compare`: `1.9.5 lt 1.10.0`、`156.0.8078.9 lt 156.0.8078.81`、`77.1 lt 77.1_1`、`5.10.2 GM (b5299, 5a516b44) eq 5.10.2`、`1.2.3-beta lt 1.2.3`、`1.2.3-alpha` と `1.2.3-beta` は終了コード 2、数字でない入力は終了コード 2。
5. 層1の鮮度: KEV、JVN iPedia、JVN、JPCERT/CC のそれぞれについて、`VULNCHECK_NOW` を最新の日付の 14 日後より後にすると `warn`、前にすると `ok` になる。取得できた期間が `evidence.period` に入っている。
6. 項目ごとの要確認: バージョン不明や `unmapped` の項目があってもエンベロープは `ok` のままで、その項目に `review` が付き、`evidence.review` に件数が入る。

`tests/run` は全項目の結果を表示し、1 つでも失敗すれば終了コード 1。ネットワークが必要な試験（3）はそう明記する。
最初の本番実行のレポートは、人が見てヤバさの一文と優先度の妥当性を確認する（自動試験の対象外）。

## 13. 対象外

- プロジェクトの依存関係（別の仕組みとして後で設計する）
- Docker イメージ、Claude Code のプラグインと MCP サーバー、pip の user パッケージ
- 定期実行、自動更新
