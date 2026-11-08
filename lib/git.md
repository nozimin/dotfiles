# git と GitHub (gh)

git と gh は Brewfile の `brew "git"` と `brew "gh"` でインストールする。brew の PATH が先に来るので、macOS 標準の `/usr/bin/git` より brew の git が使われる。

## setup がやること

1. `gh auth status` が通らなければ、確認してから GitHub にログインする。プロトコルは HTTPS。ブラウザが開くので、表示されたワンタイムコードを入力する。

   ```sh
   gh auth login --hostname github.com --git-protocol https --web
   ```

2. git の認証に gh を使う設定がなければ、確認してから設定する。

   ```sh
   gh auth setup-git --hostname github.com
   ```

3. `user.name` と `user.email` が未設定なら、入力してもらって `~/.gitconfig` に書き込む。デフォルト値は GitHub から取得する。
   - name: GitHub の名前。空ならユーザー名。
   - email: GitHub で公開しているメールアドレス。公開していなければ `<id>+<login>@users.noreply.github.com`。

`~/.gitconfig` にはメールアドレスなどの個人情報が入るので、リポジトリでは管理しない。

## 手動でやる場合

```sh
gh auth login --hostname github.com --git-protocol https --web
gh auth setup-git --hostname github.com
git config --global user.name "<name>"
git config --global user.email "<email>"
```
