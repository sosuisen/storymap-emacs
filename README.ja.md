[README (English)](README.md)

# Emacs用story-mapping

Markdownのアウトラインをユーザーストーリーマップとして表示するEmacsパッケージです。
VS Code拡張機能[Story Mapping](https://github.com/sosuisen/vscode-user-story-mapping)のEmacs版です。
どちらも、Rustのクレート[storymap](https://crates.io/crates/storymap)でマップを描きます。

## 動作環境

- Windows 11
- Emacs 31.1（グラフィカルなフレーム、PNG対応）
- Rust 1.99（描画プログラムのビルドに使います）

## インストール

描画プログラムをビルドします。

```sh
cargo build --release
```

パッケージは、`story-mapping.el`の隣の`target/release`からプログラムを探します。
`cargo install --path .`で`PATH`に置くこともできます。

初期化ファイルに次を追加します。

```elisp
(add-to-list 'load-path "/path/to/story-mapping")
(autoload 'story-mapping "story-mapping" nil t)
(autoload 'story-mapping-export-svg "story-mapping" nil t)
```

## 使い方

`.md`ファイルを開いて、次のコマンドを実行します。

| コマンド | 動作 |
|---|---|
| `M-x story-mapping` | 右にパネルを開き、マップを表示します。編集に追従します。保存前の内容も反映します。 |
| `M-x story-mapping-export-svg` | マップをSVGファイルに保存します。`RET`を押すだけで、`.md`の隣の同名の`.svg`に保存します。 |

パネルでは次のキーを使えます。

| キー | 動作 |
|---|---|
| `+`または`=` | 拡大 |
| `-` | 縮小 |
| `0` | 100%に戻す |
| 矢印キー、`C-n`、`C-p`、`C-f`、`C-b`、`C-v`、`M-v`、マウスホイール | スクロール |
| `g` | 描き直す |
| `q` | パネルを閉じる |

アウトラインの書式はVS Code拡張機能と同じです。
[そのREADME](https://github.com/sosuisen/vscode-user-story-mapping/blob/main/README.ja.md)を参照してください。

## 設定

`M-x customize-group RET story-mapping`で変更できます。

| 変数 | 既定値 | 意味 |
|---|---|---|
| `story-mapping-program` | `"story-mapping-render"` | 描画プログラム |
| `story-mapping-window-width` | `0.5` | パネルの幅（フレームに対する割合） |
| `story-mapping-update-delay` | `0.3` | 編集のあと、更新するまでに待つ秒数 |
| `story-mapping-scale` | `1.0` | 100%のときの、マップの1pxあたりの画像のピクセル数。高解像度の画面でマップが小さく見えるときは`2.0`にします |

パネルを別の場所に開くには、`*Story Map: ...*`のバッファの規則を`display-buffer-alist`に追加します。

## 制限

- プレビューは画像なので、マップ内のリンクはクリックできません。
- パネルにはグラフィカルなフレームが必要です。端末では使えません。
- 文字はOSのフォントで描きます。SVGファイルは総称フォント`sans-serif`を指定するだけなので、別のマシンでは見た目が変わることがあります。

## 開発

```sh
cargo fmt --check
cargo clippy --all-targets
cargo test
cargo build --release
emacs -Q --batch -L . -l test/story-mapping-tests.el -f ert-run-tests-batch-and-exit
```

Emacsのテストは、描画プログラムのリリースビルドを実行します。

カバレッジとミューテーションテストの手順は、[README.md](README.md#coverage-and-mutation-testing)にあります。

## ライセンス

MIT
