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
- 指摘は優先度ごとにチャットに表示する。前回のレポートと比べて `[新規]` / `[継続]` / `[解消]` を付ける。

  | 優先度 | 条件 | 対応の目安 |
  |---|---|---|
  | P0 | KEV に掲載、実際の悪用の報告あり、または VS Code 拡張が Malware として削除されている | 今日中 |
  | P1 | CVSS 9.0 以上、または信頼できない入力を扱うアプリでリモートから攻撃できる | 今週中 |
  | P2 | それ以外（EOL、ローカルからのみ攻撃可能など） | 次に更新するとき |

- 取得に失敗したソースや、結果を信用しきれないソース（件数 0、取得範囲の不足など）は「⚠ソース異常」として表示する。「該当なし（全ソース正常）」と出るのは、すべてのソースが正常なときだけ。

### 対象

| 対象 | 照合の方法 |
|---|---|
| brew の formula と、.app を持たない cask（`claude-code` など） | formulae.brew.sh の最新版と比べる |
| `/Applications` のアプリ | App Store のものは iTunes Lookup、それ以外は brew の cask の最新版と比べる（brew で入れたかは問わない） |
| macOS（Safari を含む） | `softwareupdate --list` |
| Ruby 本体（rbenv） | endoflife.date の同じサイクルの最新パッチと EOL |
| npm / pnpm のグローバルパッケージ、uv のツール、gem | OSV.dev |
| VS Code 拡張 | Marketplace の削除済み一覧 |

- 新しいバージョンがあるものは、間のセキュリティ修正を Claude がリリースノートやアドバイザリで調べ、修正版よりインストール済みが古いものだけを指摘にする。セキュリティ修正が見つからないものは「参考」に回す。
- 最新版を対応付けられなかったアプリは、Claude がベンダーのページで調べ、「要確認」とする。
- あわせて CISA KEV（全件）、JVN iPedia と JVN（直近 30 日）、JPCERT/CC 注意喚起（直近 30 日）をインベントリと照合する。

### 対象外

- プロジェクトの依存関係
- Docker イメージ
- Claude Code のプラグインと MCP サーバー
- pip の user パッケージ
- 定期実行と自動更新

### レポートの保存先

`~/Documents/vuln-check/reports/YYYYMMDDhhmmss.md` と、同じ名前の `.json`（次回の差分の判定に使う）。古いレポートは削除しない。

### 外部に送る情報

- OSV.dev（`api.osv.dev`）に、npm / pnpm / uv / gem のパッケージ名とバージョンを送る。
- formulae.brew.sh には formula ごとに問い合わせるので、URL に formula 名が入る。cask は一覧全体を 1 回取得する。
- iTunes Lookup（`itunes.apple.com`）に、App Store のアプリの bundle id を送る。
- endoflife.date、CISA KEV、JVN、JPCERT/CC、VS Code の削除済み一覧（GitHub）は、公開データを取得するだけ。
- Claude がリリースノートなどを調べるときは、アプリ名やバージョンが Web 検索や取得する URL に入る。インベントリの内容は Claude との会話に含まれる。

### スクリプトを直接使う

収集や照合は `scripts/vulncheck` が行う。結果は JSON で出る。

```sh
~/.claude/skills/vuln-check/scripts/vulncheck inventory             # インベントリだけ
~/.claude/skills/vuln-check/scripts/vulncheck all                   # すべてのソース
~/.claude/skills/vuln-check/scripts/vulncheck compare 1.9.5 1.10.0  # lt を出す
~/.claude/skills/vuln-check/tests/run                               # 試験
```
