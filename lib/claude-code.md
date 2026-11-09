# Claude Code

Claude Code は Brewfile の `cask "claude-code"` でインストールする。自作の skill は `lib/claude/skills/<名前>/` に置いてリポジトリで管理する。

## setup がやること

`lib/claude/skills/` の中のディレクトリごとに、`~/.claude/skills/<名前>` をそのディレクトリへのシンボリックリンクにする。

- `~/.claude/skills` 自体はリンクにしない。リポジトリの外で入れた skill はそのまま残る。
- 同じ名前のディレクトリやファイルがあれば、中身を表示し、確認してから `~/.claude/skills-backup/<名前>.backup-<日時>` に退避する。`~/.claude/skills` の中に退避すると、退避したものも skill として読み込まれるため。
- 別の場所へのリンク（リポジトリを移動した場合など）なら、確認してから張り替える。
- `lib/claude/skills/` が無いか空なら何もしない。

skill を追加するときは `lib/claude/skills/<名前>/SKILL.md` を置き、`cmd/setup` を実行する。リンクなので、既にある skill の編集はすぐ反映される。

## 手動でやる場合

```sh
mkdir -p ~/.claude/skills
ln -s "$(pwd)/lib/claude/skills/vuln-check" ~/.claude/skills/vuln-check
```

## /vuln-check

この Mac に入っているアプリやライブラリのうち、脆弱性のあるものを一覧にする。仕様は [docs/specs/vuln-check.md](../docs/specs/vuln-check.md)。

### 使い方

Claude Code で `/vuln-check` と打つ。手動実行専用で、Claude が自分の判断で実行することはない。

- 読み取り専用。パッケージやアプリ、brew のメタデータを変更しない（`brew update` / `brew upgrade` も実行しない）。更新コマンドは表示するだけなので、自分で実行する。
- 指摘は優先度ごとにチャットに表示する。件数は対象（アプリやパッケージ）の数で、対象ごとに放置すると何が起きるかの一文と更新コマンドを付ける。前回のレポートと比べて `[新規]` / `[継続]` / `[解消]` を付ける。

  | 優先度 | 条件 | 対応の目安 |
  |---|---|---|
  | P0 | KEV に掲載、実際の悪用の報告あり、または VS Code 拡張が Malware として削除されている | 今日中 |
  | P1 | CVSS 9.0 以上、または信頼できない入力を扱うアプリでリモートから攻撃できる | 今週中 |
  | P2 | それ以外（EOL、ローカルからのみ攻撃可能など） | 次に更新するとき |

- 見出しの「⚠ソース異常 N件」は、取得元そのものの異常の数。取得失敗、件数 0、鮮度切れ（最新の日付が 14 日以上前）、一部の取得の失敗などが当たる。
- 見出しの「要確認 M件」は、ソースは正常だが、Claude が調べても判定できなかった対象の数（個別に要確認）。バージョンを読めないもの（例: Steam）や、層1の候補のうち当たるか決めきれないものが当たる。Claude がベンダーのページで確かめられたもの（AI 確認）は数えない。
- 指摘もソース異常も無ければ、見出しは「該当なし（全ソース正常）」になる。

### 対象

| 対象 | 照合の方法 |
|---|---|
| brew の formula と、.app を持たない cask（`claude-code` など） | formulae.brew.sh の最新版と比べる |
| `/Applications` と `~/Applications` のアプリ（サブフォルダの中も 3 階層まで） | App Store のものは iTunes Lookup、それ以外は brew の cask の最新版と比べる（brew で入れたかは問わない） |
| macOS（Safari を含む） | `softwareupdate --list` |
| Ruby 本体（rbenv） | endoflife.date の同じサイクルの最新パッチと EOL |
| npm / pnpm のグローバルパッケージ、uv のツール、gem（rbenv の各 Ruby） | OSV.dev |
| VS Code 拡張 | Marketplace の削除済み一覧 |

- 新しいバージョンがあるものは、間のセキュリティ修正（ベンダーがセキュリティの修正と明記したもの、または CVE かアドバイザリ ID が付いたもの）を Claude がリリースノートやアドバイザリで調べる。インストール済みの版が影響を受ける範囲（修正版より前。下限があればそれ以降）にあるものだけを指摘にする。版の比較は Claude ではなくスクリプトが行う。macOS 以外だけに当たる修正は除き、セキュリティ修正が見つからないものは「参考」に回す。
- EOL（サポートの切れた Ruby のサイクルなど）も指摘にする。
- 最新版を対応付けられなかったものや、バージョンを読めないものは、Claude がベンダーのページで調べる。確かめられれば「AI 確認」として、読んだ URL とバージョンを根拠にほかと同じように判定する。後継のアプリに置き換わって更新が止まったもの（例: 旧版の Keynote）は EOL として扱う。判定できないものだけを「個別に要確認」とする。
- あわせて CISA KEV（全件）と、JVN iPedia、JVN、JPCERT/CC 注意喚起（RSS が持っている範囲。JVN iPedia は 1〜2 日分、JVN は 10 日前後）をインベントリと照合する。取得できた期間はレポートに書く。範囲の外の脆弱性も、インストール済みのものは上の照合で拾う。
- 各ソースが更新を止めていないかも確かめ、最新の日付が 14 日以上前ならソース異常にする。

### 対象外

- プロジェクトの依存関係
- Docker イメージ
- Claude Code のプラグインと MCP サーバー
- pip の user パッケージ
- 定期実行と自動更新

### レポートの保存先

`~/Documents/vuln-check/reports/YYYYMMDDhhmmss.md` と、同じ名前の `.json`（次回の差分の判定に使う）。古いレポートは削除しない。

レポートには指摘の一覧のほか、ソースごとの状態（層1は取得できた期間と最新の日付）、個別に要確認と AI 確認の一覧（調べた URL）も書く。

### 外部に送る情報

- OSV.dev（`api.osv.dev`）: 言語パッケージ（npm / pnpm / uv / gem）の名前とバージョン
- formulae.brew.sh: formula 名（formula ごとに問い合わせるので URL に入る。cask は一覧全体を 1 回取得するだけ）
- iTunes Lookup（`itunes.apple.com`）: App Store のアプリの bundle id
- WebSearch / WebFetch: Claude がリリースノートなどを調べるときの、アプリ名とバージョン
- Claude（Anthropic）: インベントリとスクリプトの出力（Claude との会話の内容として送られる）

endoflife.date、CISA KEV、JVN、JPCERT/CC、VS Code の削除済み一覧（GitHub）からは、公開データを取得するだけ。

### スクリプトを直接使う

収集や照合は `scripts/vulncheck` が行う。結果は JSON（ソースごとのエンベロープの配列）で出る。

```sh
~/.claude/skills/vuln-check/scripts/vulncheck inventory             # インベントリだけ
~/.claude/skills/vuln-check/scripts/vulncheck all                   # すべてのソース（数百 KB になる）
~/.claude/skills/vuln-check/scripts/vulncheck all --save            # 同じものを一時ファイルに保存し、パスだけを出す
~/.claude/skills/vuln-check/scripts/vulncheck compare 1.9.5 1.10.0  # lt を出す
~/.claude/skills/vuln-check/tests/run                               # 試験
```

`all --save` で保存したファイルから、ソース異常だけを見る例:

```sh
jq '.[] | select(.status != "ok") | {layer, source, status, notes}' <表示されたパス>
```
