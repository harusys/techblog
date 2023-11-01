---
title: "Zenn の Markdown 記法一覧"
emoji: "👩‍💻"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["zenn"]
published: false
---

@[card](https://zenn.dev/zenn/articles/markdown-guide)

## 要点

- アクセシビリティの観点から `見出し2` から始める。
- 画像の表示が大きすぎる場合は、URL の後に半角スペースを空けて `=○○x` と記述すると、画像の幅を px 単位で指定できます。

```
![altテキスト](https://画像のURL =250x)
```

- 画像のすぐ下の行に`*`で挟んだテキストを配置すると、キャプションのような見た目で表示されます。

```
![](https://画像のURL)
*キャプション*
```

- 言語:ファイル名と:区切りで記載することで、ファイル名がコードブロックの上部に表示されます。

```js:fooBar.js
const great = () => {
  console.log("Awesome")
}
```

- diff と言語名を半角スペース区切りで指定することで、diff のシンタックスハイライトが有効になります。

```diff js
+    const foo = bar.baz([1, 2, 3]) + 1;
-    let foo = bar.baz([1, 2, 3]);
```

- GitHub 上のファイルへの URL またはパーマリンクだけの行を作成すると、その部分に GitHub の埋め込みが表示されます。

https://github.com/octocat/Hello-World/blob/master/README

## メッセージ

```
:::message
メッセージをここに
:::
```

:::message
メッセージをここに
:::

```
:::message alert
警告メッセージをここに
:::
```

:::message alert
警告メッセージをここに
:::

## アコーディオン（トグル）

```
:::details タイトル
表示したい内容
:::
```

:::details タイトル
表示したい内容
:::

:::message
「detail」ではなく「details」です。
:::

### 要素をネストさせるには

外側の要素の開始/終了に `:` を追加します。

```
::::details タイトル
:::message
ネストされた要素
:::
::::
```

::::details タイトル
:::message
ネストされた要素
:::
::::
