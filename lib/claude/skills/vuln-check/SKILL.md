---
name: vuln-check
description: この Mac に入っているアプリやライブラリの脆弱性を調べ、優先度を付けてチャットとレポートに出す。読み取り専用。
disable-model-invocation: true
allowed-tools:
  - Bash(~/.claude/skills/vuln-check/scripts/vulncheck *)
  - Bash(jq *)
  - Edit(//private/tmp/vuln-check-all.json)
  - Read(~/Documents/vuln-check/**)
  - Edit(~/Documents/vuln-check/**)
  - WebFetch
  - WebSearch
---

# vuln-check

この Mac に入っているアプリやライブラリのうち、脆弱性のあるものを一覧にし、優先度を付けてチャットとレポートに出す。

## 守ること

- **読み取り専用**。実行するのは `vulncheck`、`jq`、`ls` と、WebSearch / WebFetch での調査だけ。パッケージやアプリ、brew のメタデータを変えるコマンド（`brew update` / `brew upgrade` を含む）は更新コマンドとして提示するまでにし、実行はユーザーに任せる。
- `vulncheck` は `~/.claude/skills/vuln-check/scripts/vulncheck` のこと。`allowed-tools` がこの書き方で許可しているので、`~` から始まるこのパスのまま実行する。
- バージョンの大小は `vulncheck compare <インストール済み> <修正版>` の出力で決める。`lt` なら該当、`eq` / `gt` なら修正済み、終了コード 2 なら比較不能として要確認にする。
- 書くのは、取得したデータと読んだページに書いてあることだけ。読んだページの URL は根拠として残す。
- 出力はすべて日本語。

## 用語

- **対象**: `kind` と `name` の組（例: `app Google Chrome`、`gem rack`）。
- **指摘**: 対象 1 つと脆弱性 1 つの組。同一性は key `<kind>:<name>:<ID>` で判定する。ID は次の順に決める。
  - `osv` の項目は `id`（GHSA など）。
  - VS Code 拡張の削除は、削除一覧の拡張 ID。
  - EOL は `eol:<サイクル>`。
  - それ以外は CVE。無ければベンダーのアドバイザリ ID、それも無ければ `fix:<修正版>`。
  - 同じ対象の同じ脆弱性を複数のソースで見つけたら（OSV の `aliases` と KEV の CVE が同じなど）、1 つの指摘にまとめ、`ids` にすべての ID を入れる。対象が違えば（Ruby 本体と、その Ruby に入った gem など）別の指摘にする。
- **セキュリティ修正**: リリースノートやアドバイザリがセキュリティの修正と明記しているもの、または CVE やアドバイザリ ID が付いたもの。メモリ破壊などの不具合の修正でも、そう明記されていなければ参考の補足に書く。
- **参考**: 新しいバージョンはあるが、セキュリティ修正が見つからなかった対象。
- **要確認**: 結果を信用しきれないもの。`status: "warn"` のエンベロープと、AI が調べて決めきれなかった項目（unmapped、バージョン不明、比較不能、層1の候補で該当するかを確かめられなかったもの）。
- **取得失敗**: `status: "error"` のエンベロープ。
- **ソース異常**: 要確認と取得失敗の合計（エンベロープの数 + 要確認にした項目の数）。

## 手順

### 1. 収集する

```sh
~/.claude/skills/vuln-check/scripts/vulncheck all > /private/tmp/vuln-check-all.json
```

出力は数百 KB ある。以降は `jq` で `layer` と `source` ごと、対象ごとに必要な部分だけを読む。まず全体を見る。

```sh
jq -r '.[] | [.layer, .source, .status, .count, (.items | length), (.notes | join(" / "))] | @tsv' /private/tmp/vuln-check-all.json
```

- 終了コードが 0 でないか、出力が JSON の配列でなければ、エラーの内容をチャットに出して終える。
- エンベロープは `{source, layer, status, count, fetched_at, evidence, notes, items}`。`count` はそのソースで読み取った件数、`evidence` は「該当なし」の根拠（読んだ URL、件数、取得できた期間など）、`notes` は補足。インベントリの `source` は kind 名で、層2の `vscode` と同じ名前になるので、`layer` と `source` の組で区別する。
- `items` の形:

  | layer / source | 項目 |
  |---|---|
  | inventory / 各 kind | `kind` `name` `version` `origin` `bundle_id` `path` |
  | layer2 / `osv` | `kind` `name` `version` `ecosystem` `origin` `id` `aliases` `summary` `severity`（`[{type, score, vector}]`）`rating` `fixed`（配列） |
  | layer2 / `brew-api` `cask-api` `itunes` `softwareupdate` `endoflife` | `kind` `name` `installed` `latest` `outdated` `method` `eol` `update_command` `matched` |
  | layer2 / `vscode` | `id` `version` `removal_date` `type` |
  | layer1 / `kev` | `cve` `vendor` `product` `name` `date_added` `ransomware` `references` `tokens` `matched` |
  | layer1 / `jvn-ipedia` `jvn` | `id` `title` `link` `published` `cves` `cpe` `cvss` `description` `tokens` `matched` |
  | layer1 / `jpcert` | `id` `title` `link` `published` `cves` |

  `matched` は、その候補と名前が一致したインベントリの `"<kind> <name>"` の一覧。

完了条件: すべてのエンベロープを、状態（`ok` → OK、`warn` → 要確認、`error` → 取得失敗）付きでソース健全性の表（「出力」の節）の下書きに移した。

### 2. 層2の脆弱性を確定する

**osv**: 項目をすべて指摘にする。

- gem は Ruby ごと、版ごとに項目が出る。同じ対象で同じ `id` の項目は 1 つの指摘にまとめ、該当した版をすべて現在のバージョンに書く。
- 修正版は、該当した版ごとに選ぶ。`fixed` が複数あるとき（系列ごとの修正版。例: `3.0.1` `3.1.2` `3.2.3`）は、その版との `compare` が `lt` になるもののうち最小を選ぶ。版が複数の系列にまたがれば修正版も版ごとに違うので、`7.2.1 → 7.2.3.2, 8.0.2 → 8.0.5.1` のように版と組にして書く。
- 更新コマンドは次の形で書く。
  - npm: `npm install -g <name>@latest`
  - pnpm: `pnpm add -g <name>@latest`
  - uv: `uv tool upgrade <name>`
  - gem: `RBENV_VERSION=<origin の版> gem update <name>`。古い版も照合の対象になるので、該当した版が複数あれば `gem cleanup <name>` を添える。

**latest**（`brew-api` `cask-api` `itunes` `softwareupdate` `endoflife`）: 調べるのは次の項目。

```sh
jq -c '.[] | select(.layer == "layer2" and (.source | IN("brew-api", "cask-api", "itunes", "softwareupdate", "endoflife"))) | .items[] | select(.outdated != false) | {kind, name, installed, latest, outdated, method, eol, update_command}' /private/tmp/vuln-check-all.json
```

- `outdated: true` は**全件**、インストール済みと最新版の間のセキュリティ修正を、リリースノート、NVD、ベンダーのアドバイザリで調べる。CVE（無ければアドバイザリ ID）と修正版を抜き出し、`compare` が `lt` のものだけを指摘にする。macOS 以外だけに影響する修正（Windows のインストーラなど）は除く。セキュリティ修正が見つからなければ参考に回す。どちらも読んだ URL を残す。
  - ベンダーのセキュリティのページに修正版ごとの一覧があれば、それを最初に読む（例: Docker は <https://docs.docker.com/security/security-announcements/>）。
  - NVD の画面（`nvd.nist.gov/vuln/detail/...`）は WebFetch では中身が取れない。CVE の内容とスコアは `https://cveawg.mitre.org/api/cve/<CVE>` か `https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=<CVE>` で読む。
- `macos` は `softwareupdate --list` に更新が出ているものが `outdated: true` になる。Apple のセキュリティアップデートの一覧（<https://support.apple.com/ja-jp/100100>）で、その更新の修正内容を調べる。
- `method: "unmapped"` は、ベンダーのページで最新版を調べ、読んだ URL とバージョンを根拠に記録して要確認にする。最新版がインストール済みより新しければ（`compare` が `lt`）、`outdated: true` と同じ調べ方もする。
- `installed: null`（バージョン不明）は比べられないので要確認にし、インベントリの `notes` にある参考値（`CFBundleVersion` など）を根拠に添える。
- `eol` の日付が実行日以前なら EOL の指摘にする（ID は `eol:<matched のサイクル>`、修正版はサポート中のサイクルの最新版）。
- 更新コマンドは項目の `update_command` を使う。

**vscode**（layer2）: 一致した拡張をすべて指摘にする。

完了条件: `osv` の全項目が指摘になり、`outdated: true` の全件が指摘か参考のどちらかになって読んだ URL が付き、unmapped とバージョン不明の全件が要確認になって根拠が付いた。

### 3. 層1を照合する

KEV、JVN iPedia、JVN の候補は、拾い過ぎ側に倒した名前の一致なので（KEV だけで百件以上ある）、対象ごとにまとめてから調べる。

```sh
jq -r '.[] | select(.layer == "layer1" and .source == "kev") | [.items[] | .matched[] as $m | {m: $m, product: "\(.vendor) \(.product)", date_added}] | group_by(.m)[] | "\(length)件\t\(.[0].m)\t最新 \([.[].date_added] | max)\t\([.[].product] | unique | join(" / "))"' /private/tmp/vuln-check-all.json
```

1. **誤一致を落とす**: 候補の製品（KEV の `vendor` と `product`、JVN の `title` と `cpe`）が、その対象そのものか、対象に同梱された部品でなければ落とす。例: LINE と Jenkins Command Line Interface、`google` の一致による omniauth-google-oauth2 と Chromium、`rails` の一致による rubocop-rails と Ruby on Rails。影響を受けるのが macOS 以外の版だけ（「Windows 上の」「Android 版」「iOS 版」など）と書かれた候補も落とす。
2. **絞り込む**: KEV は修正版を持たないので、対象ごとに次のように絞ってから調べる。対象の候補を新しい順に並べるには次のようにする。

   ```sh
   jq -r --arg t 'app Google Chrome' '.[] | select(.layer == "layer1" and .source == "kev") | .items | map(select(any(.matched[]; . == $t))) | sort_by(.date_added) | reverse[] | [.date_added, .cve, .name, (.references | join(" "))] | @tsv' /private/tmp/vuln-check-all.json
   ```

   - **累積修正**の製品（Chrome、macOS、Safari など、新しい版が過去の修正をすべて含むもの）:
     - 層2で最新（`outdated: false`）なら、修正が出ている KEV は修正済みとみなす。`date_added` が直近 30 日の項目だけ、まだ修正が出ていないかを確かめる。
     - 古い版（`outdated: true`）なら、`date_added` が新しい順に修正版を調べ、インストール済みの版がその修正を含むところ（`compare` が `eq` か `gt`）まで確かめる。それより古い項目は修正済みとみなす。
   - 複数の系列を並行して保守する製品（Rails など）は、インストール済みの系列ごとに確かめる。
   - それ以外は候補ごとに、`references` やアドバイザリから影響バージョンか修正版を抜き出して確かめる。
3. **確かめる**: 抜き出した修正版とインストール済みを `compare` で比べる。JVN iPedia と JVN は `description` に修正版が書かれていることが多い（Chrome なら数十件が同じ修正版を持つので、`compare` は修正版ごとに 1 回でよい）。`cvss` があればトリアージに使う。
4. **JPCERT/CC 注意喚起**は全件が出る（`matched` は無い）。題名の製品がインベントリにあるかを見て、あれば同じように確かめる。
5. 該当したものを指摘にする。層2の指摘と同じ脆弱性なら 1 つにまとめ、層1のソースを判定の根拠に足す。
6. 調べても対象に当たるかを確かめられない候補（同梱しているかが分からない部品の KEV など）は、要確認にして読んだ URL を根拠に書く。

完了条件: 候補が一致した対象と JPCERT/CC の全件が、「誤一致」「修正済み（根拠は `compare` の結果か、上の絞り込みの規則）」「該当」「要確認」のどれかに分かれた。

### 4. クロスチェックする

層1で該当した対象のうち、層2で同じ対象が指摘にも `outdated: true` にもなっていないものを、「層2未検出: <対象> <ID>」としてソース健全性の表に書く。

### 5. トリアージする

各指摘に、優先度と放置すると何が起きるかの一文を付ける（「トリアージ」の節）。

完了条件: すべての指摘に優先度、一文、判定の根拠がある。

### 6. 差分のタグを付ける

前回のレポートを探す（名前が日時なので最後のものが最新）。

```sh
ls -1 ~/Documents/vuln-check/reports/*.json | tail -n 1
```

- 何も出ないか、ファイルが無いというエラー（zsh なら `no matches found`）になれば、前回は無い。すべての指摘を `[新規]` にする。
- 前回があれば `jq` でその `findings` を読み、key で突き合わせる。今回だけにあるものは `[新規]`、両方にあるものは `[継続]`、前回だけにあるものは `[解消]`。key が違っても、同じ対象で `ids` が重なれば同じ指摘とみなす。

### 7. 保存して出力する

1. レポートの名前（`YYYYMMDDhhmmss`）を実行日時から作る。

   ```sh
   jq -r '[.[].fetched_at] | min | .[0:19] | gsub("[-T:]"; "")' /private/tmp/vuln-check-all.json
   ```

2. Write で `~/Documents/vuln-check/reports/<名前>.md` と `~/Documents/vuln-check/reports/<名前>.json` を書く（「出力」の節）。ディレクトリが無ければ Write が作る。前回までのレポートはそのまま残す。
3. チャットにサマリーを出す（「出力」の節）。

## トリアージ

### 優先度

上から順に当てはめ、最初に当たったものにする。

| 優先度 | 条件 | 対応の目安 |
|---|---|---|
| P0 | KEV に掲載、実際の悪用の報告あり、または VS Code 拡張が Malware として削除されている | 今日中 |
| P1 | CVSS 9.0 以上、または信頼できない入力を扱うアプリでリモートから攻撃できる | 今週中 |
| P2 | 上記以外（CVSS 7.0 以上、EOL、それ未満、ローカルからのみ攻撃可能、Malware 以外の種別で削除された拡張） | 次に更新するとき |

- KEV、CVSS、EOL、削除種別（`type`）は、取得したデータでそのまま判定する。
- 実際の悪用の報告は、ベンダーのアドバイザリやリリースノートの記述（"may have been exploited"、"an exploit ... exists in the wild" など）で判定し、その URL を根拠に書く。
- CVSS は `severity` の数値の `score` を使う（複数あれば最大）。数値が無ければ GHSA の `rating` で代え、`CRITICAL` は 9.0 以上、`HIGH` は 7.0 以上として扱う。どちらも無いとき（AI が調べて見つけた CVE もこれに当たる）だけ NVD などでスコアを確かめ、確かめた URL を根拠に書く。スコアがどこにも無ければ（CVE の無いベンダーの修正など）、根拠に「CVSS なし」と書き、ほかの条件に当たらなければ P2 にする。
- 信頼できない入力を扱うアプリは、ブラウザ、チャット、メール、PDF、メディア、Docker など、外から届くデータを開くアプリやコマンド。当たると判断した理由を根拠に書く。リモートから攻撃できるかは、CVSS のベクターの `AV:N` かアドバイザリの記述で判断する。gem や npm などのライブラリは、どのアプリが使うかが分からないので CVSS で判定する。
- 対象の優先度は、その対象の指摘のうち最も高いもの。
- EPSS は使わない。

### 放置すると何が起きるかの一文

- 形式は「〈きっかけ〉だけで、〈起きること〉」に感嘆符を付ける。感嘆符は P0 が `！！！`、P1 が `！！`、P2 が `！`。
- アドバイザリに書かれた影響の範囲で書く。影響の種類ごとの書き方:
  - リモートからのコード実行 →「PC を乗っ取られる」
  - 情報漏えい →「〜が抜き取られる」
  - 権限昇格 →「管理者権限を奪われる」
  - DoS →「アプリを落とされる」
  - 詳細が非公開 →「詳細は非公開。最悪の場合〜」
- 例:「細工された Web ページを開くだけで、PC を乗っ取られる！！！」
- 一文は対象と優先度の組ごとに 1 つ書き、その組の指摘で共有する（その組で最も重い影響で書く）。対象の一文は、その対象の優先度の一文。

## 出力

### チャットのサマリー

```
【P0】1件 【P1】1件 【P2】4件 ／ ⚠ソース異常 1件

P0 [新規] Google Chrome 156.0.8078.81 → 156.0.8079.12
  細工された Web ページを開くだけで、PC を乗っ取られる！！！
  → Chrome を再起動して更新
P1 [継続] Postman 11.44.0 → 12.34.0
  悪意ある API 定義を読み込むだけで、手元の認証情報が抜き取られる！！
  → brew upgrade --cask postman
P2 4件: ruby, rack, nokogiri, lz4
[解消] 2件 ／ ⚠ jvn-ipedia（層1）: 取得失敗

レポート: ~/Documents/vuln-check/reports/20261109153000.md
```

- 件数は**対象**の数。同じ対象の指摘は 1 つにまとめ、その対象の優先度で数える。
- 1 行目の見出しは次のどれか。

  | 状態 | 見出し |
  |---|---|
  | 指摘あり | `【P0】N件 【P1】N件 【P2】N件`（0 件の優先度も書く）。ソース異常があれば ` ／ ⚠ソース異常 N件` を続ける |
  | 指摘なし・ソース異常あり | `⚠ソース異常あり：N件。該当なし` |
  | 指摘なし・全ソース正常 | `該当なし（全ソース正常）` |

- P0 と P1 は対象ごとに 3 行。`P<n> [タグ] <対象> <現在> → <修正版>`、一文、`→ <更新コマンド>`。
  - 修正版は、その対象の指摘の修正版のうち最大のもの（すべてを直す版）。現在の版が複数あれば、版ごとに `<版> → <修正版>` を `, ` でつなぐ（例: `activestorage 7.2.1 → 7.2.3.2, 8.0.2 → 8.0.5.1`）。修正版が同じ版は `0.23.14, 0.23.15 → 0.26.9` のようにまとめる。
  - タグは、その対象に `[新規]` の指摘が 1 つでもあれば `[新規]`、無ければ `[継続]`。
- P2 は 1 行で `P2 N件: <対象名>, …`。
- 次の行に、`[解消] N件`（対象の数）と、ソース異常 1 件ごとの `⚠ <source>（<インベントリ|層1|層2>）: <要確認|取得失敗>` または `⚠ <対象>: 要確認` を ` ／ ` でつなぐ。無いものは省き、どれも無ければ行ごと省く。
- 最後の行はレポートのパス。

### レポート（.md）

次の 6 つの節を、この順に書く。

````markdown
# 脆弱性チェック 2026-11-09 15:30

## 1. サマリー

<チャットの 1 行目と同じ見出し>

- 対象: P0 N件 / P1 N件 / P2 N件（指摘は計 N件）
- 差分（指摘の数）: [新規] N件 / [継続] N件 / [解消] N件
- ソース異常: N件
- 前回のレポート: <ファイル名>（無ければ「なし」）

## 2. 指摘の一覧

### P0 [新規] Google Chrome 156.0.8078.81 → 156.0.8079.12

- 放置すると（P0）: 細工された Web ページを開くだけで、PC を乗っ取られる！！！
- 放置すると（P2）: 細工された Web ページを開くだけで、閲覧中のページの情報が抜き取られる！
- 更新: アプリ内の更新
- 判定の根拠: KEV に掲載（2026-10-27 追加）。信頼できない入力を扱うアプリ（ブラウザ）。<読んだ URL>

| 優先度 | タグ | ID | 修正版 | 判定の根拠 |
|---|---|---|---|---|
| P0 | [新規] | CVE-2026-12345 | 156.0.8079.12 | KEV（2026-10-27 追加） |
| P2 | [新規] | CVE-2026-12346 | 156.0.8079.12 | CVSS 6.5（<URL>） |

## 3. [解消]

| 対象 | ID | 前回の優先度 |
|---|---|---|

## 4. 参考（新しいバージョンはあるが、セキュリティ修正は見つからなかったもの）

| 対象 | 現在 | 最新 | 更新コマンド | 読んだ URL |
|---|---|---|---|---|

## 5. ソース健全性

| ソース | 状態 | 読み取った件数 | 根拠 | 補足 |
|---|---|---|---|---|
| 層1 kev | OK | 1769 | <URL>、全 1769 件中 候補 192 件 | |

## 6. 未チェック範囲

- プロジェクトの依存関係
- Docker イメージ
- Claude Code のプラグインと MCP サーバー
- pip の user パッケージ
````

- 2 は対象ごとの塊を優先度順に並べる。「放置すると」はその対象にある優先度ごとに 1 行。表は指摘ごとに 1 行で、ID の列には `ids` をすべて書く。
- 5 の行は、すべてのエンベロープ（インベントリ、層1、層2）、要確認にした項目（対象名と調べた URL）、層2未検出の警告。根拠は `evidence` の要点（URL、件数、取得できた期間）、補足は `notes`。

### レポート（.json）

次回の差分の判定に使う。

```json
{
  "generated_at": "2026-11-09T15:30:00+09:00",
  "previous": "20261101120000.json",
  "findings": [
    {
      "key": "app:Google Chrome:CVE-2026-12345",
      "priority": "P0",
      "tag": "新規",
      "kind": "app",
      "target": "Google Chrome",
      "installed": "156.0.8078.81",
      "fixed": "156.0.8079.12",
      "ids": ["CVE-2026-12345"],
      "line": "細工された Web ページを開くだけで、PC を乗っ取られる！！！",
      "rationale": "KEV に掲載（2026-10-27 追加）。https://...",
      "update_command": "アプリ内の更新"
    }
  ],
  "resolved": [
    {"key": "gem:rack:GHSA-xxxx-xxxx-xxxx", "priority": "P2", "kind": "gem", "target": "rack", "ids": ["GHSA-xxxx-xxxx-xxxx"]}
  ],
  "reference": [
    {"kind": "brew-formula", "target": "fmt", "installed": "12.2.0", "latest": "12.2.1", "urls": ["https://..."]}
  ],
  "sources": [
    {"layer": "layer1", "source": "kev", "state": "OK", "count": 1769, "evidence": "<URL>、全 1769 件中 候補 192 件", "notes": ""},
    {"layer": "layer2", "source": "cask-api", "target": "iLok License Manager", "state": "要確認", "count": null, "evidence": "<読んだ URL> の最新版 5.11.0", "notes": "unmapped"}
  ]
}
```

- `findings` は指摘ごとに 1 件。`installed` は該当した版、`fixed` はその修正版（版が複数なら `installed` は `, ` でつなぎ、`fixed` は `7.2.1 → 7.2.3.2, 8.0.2 → 8.0.5.1` の形にする）。`line` は対象と優先度の組の一文。
- `generated_at` は手順 7 の実行日時（`fetched_at` の最小）。`previous` は差分に使った前回の `.json` の名前で、無ければ `null`。
- `sources` は .md の 5 と同じ行。要確認にした項目には `target` を付け、層2未検出の警告は `state: "層2未検出"` にする。
