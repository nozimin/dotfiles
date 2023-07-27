# シンボリックリンクの貼り方
```sh:example
$ ln -s $(repository_path)/.zshrc ~/.zshrc
```

# ファイルの補足
- `starship.toml`
[starship](https://starship.rs/ja-jp/)
zshプロンプト拡張ライブラリの設定ファイル。

デフォルトでは、`~/.config/starship.toml`に配置すると設定を読み込んでくれるので、
以下コマンドでシンボリックリンクを貼ることで設定を読み込んでくれる。
```sh:example
$ ln -s $(repository_path)/.starship.toml ~/.config/starship.toml
```
