# シンボリックリンクの貼り方
```sh:example
$ ln -s $(repository_path)/.zshrc ~/.zshrc
```

# ファイルの補足
### `starship.toml`
[starship](https://starship.rs/ja-jp/)
zshプロンプト拡張ライブラリの設定ファイル。

デフォルトでは、`~/.config/starship.toml`に配置すると設定を読み込んでくれるので、
以下コマンドでシンボリックリンクを貼ることで設定を読み込んでくれる。
```sh:example
$ ln -s $(repository_path)/.starship.toml ~/.config/starship.toml
```

### `com.googlecode.iterm2.plist`
iterm2の設定ファイル。
iterm2で設定ファイルを読み込むには、アプリケーション側の設定でファイルパスの指定が必要になる。

```sh:example
$ ln -s $(repository_path)/com.googlecode.iterm2.plist $(yourself_item2_config_filepath)/com.googlecode.iterm2.plist
```
