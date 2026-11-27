# architecture

## 全体像

Markdownのアウトラインを、Emacsの右パネルにストーリーマップとして表示するパッケージである。画面はプレビューのパネルだけである。

部品は2つある。

- `story-mapping.el`: Emacsのパッケージ。コマンド、パネル、編集への追従を担う。
- `src/main.rs`: 描画プログラム`story-mapping-render`。crates.ioの`storymap`を呼ぶだけの薄いCLIである。

依存の向きは`story-mapping.el` → `story-mapping-render` → `storymap`である。

## 外部とのやり取り

- `story-mapping-render svg`または`png [倍率]`を外部プロセスとして起動する。
- 標準入力へUTF-8のアウトラインを渡し、標準出力から画像を受け取る。
- 失敗のときは、終了コードが0以外になり、標準エラーに理由が出る。Emacsは標準出力と標準エラーを同じバッファで受ける。プログラムは失敗のときに画像を書かず、成功のときに標準エラーへ書かないためである。
- ファイルに書くのは`story-mapping-export-svg`だけである。プレビューの画像はメモリにだけ置く。

## 状態

元のバッファは、`story-mapping--preview`、`--timer`、`--process`、`--render-again`を持つ。`revert-buffer`やメジャーモードの変更でも消えないよう、変数とフックをpermanent localにしている。

プレビューのバッファは、`story-mapping--source`、`--zoom`、`--image-zoom`を持つ。`--image-zoom`は、表示中の画像を描いたときの倍率である。描画のプロセスは、描いた倍率をプロパティ`zoom`に持つ。

## 主な処理の流れ

プレビューを開く流れは次のとおりである。

1. `story-mapping`が`.md`とプログラムの有無を確かめる。
2. `story-mapping--create-preview`がプレビューのバッファを作り、元のバッファにフックを付ける。
3. `display-buffer`で右のサイドウィンドウに表示する。
4. `story-mapping--render`がプロセスを起動し、本文を送る。
5. 終了すると、センチネルから`story-mapping--finish-render`が呼ばれ、`story-mapping--show-image`が画像を差し替える。

編集に追従する流れは次のとおりである。

1. `after-change-functions`の`story-mapping--schedule-update`が、タイマーを張り直す。
2. タイマーの`story-mapping--update`が、パネルが見えていれば`story-mapping--render`を呼ぶ。
3. 描画中なら`story-mapping--render-again`を立て、終了後にもう一度描く。

ズームの流れは次のとおりである。

1. `story-mapping--apply-zoom`が倍率を変え、`story-mapping--scale-image`が今の画像を`:scale`で拡大縮小して見せる。
2. 編集と同じく`story-mapping--schedule-update`でタイマーを張り直し、待ち時間のあとに新しい倍率で描く。続けて押したズームは、1回の描画にまとまる。
3. 描き終えると、描いた倍率と今の倍率の比を`:scale`にして表示する。描画中に倍率が変わっていても、正しい大きさになる。

画像は、1文字のテキストの`display`プロパティを差し替えて更新する。テキストを変えないので、スクロールの位置が保たれる。スクロールには`image-mode`のコマンドを使う。

## 関連する文書

- `docs/features.md`: 機能の一覧
- ADRはまだない。
