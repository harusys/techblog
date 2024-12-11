---
title: "2024年お世話になったBigQueryクエリ3選"
emoji: "🔖"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["bigquery"]
publication_name: "zozotech"
published: true
published_at: 2024-12-12 00:00
---

## はじめに

2024年もあっという間に終わるということで、今年書いたBigQueryクエリの行数を振り返ってみるとざっと `約5,000行` ほどでした。その中から、特に今年お世話になったなと感じるBigQueryクエリを3つ紹介します。[^profile]

[^profile]: 筆者はデータエンジニア/データアナリストの業務でBigQueryを日々利用しており、それらの経験に基づいて独断と偏見で選んでいます。

## 最新の1件を抽出する [ ARRAY_AGG ]

履歴のようなテーブルから最新の1件のみを抽出したい場合、`ARRAY_AGG` 関数を使うと便利です。

### データ例

以下のようにレビュー履歴の記録されたテーブルがあったとします。このテーブルはレビュー内容を更新する度に変更履歴が記録されます。

| id  | review_id | star | content   | created_at          |
| --- | --------- | ---- | --------- | ------------------- |
| 1   | 1         | 4    | テスト1   | 2024-12-01T00:00:00 |
| 2   | 1         | 3    | テスト2   | 2024-12-01T00:00:01 |
| 3   | 1         | 4    | テスト3   | 2024-12-01T00:00:02 |
| 4   | 2         | 2    | コメント1 | 2024-12-02T09:01:03 |
| 5   | 2         | 3    | コメント2 | 2024-12-02T09:01:05 |

### クエリ

レビューID毎の最新状態を取得したいので、以下の流れでクエリを記述します。

1. `review_id` でグループ化
2. 取得したい列を `STRUCT` で集約
3. `created_at` の降順でソート
4. `LIMIT 1 OFFSET(0)` で1件のみ取得
5. latest列で1段ネストするので `SELECT latest.*` で展開

```sql
SELECT
  review_id,
  latest.*,
FROM (
  SELECT
    review_id,
    ARRAY_AGG(STRUCT(
      star,
      content,
      created_at
    ) ORDER BY created_at DESC LIMIT 1) [OFFSET(0)] latest,
  FROM
    reviews
  GROUP BY
    ALL
)
```

ちなみに、`QUALIFY` + `ROW_NUMBER` を使っても同様の結果を得ることができます。最新の1件と言うと `ROW_NUMBER` が有名ですが、`ARRAY_AGG` の方が計算量は少ないため、`ARRAY_AGG` を利用する方が好ましいです。

<!-- textlint-disable -->

:::details QUALIFY + ROW_NUMBERを使った場合

```sql
SELECT
  review_id,
  star,
  content,
  created_at
FROM
  reviews
QUALIFY
  ROW_NUMBER() OVER (PARTITION BY review_id ORDER BY created_at DESC) = 1
```

:::

<!-- textlint-enable -->

### 出力

| review_id | star | content   | created_at          |
| --------- | ---- | --------- | ------------------- |
| 1         | 4    | テスト3   | 2024-12-01T00:00:02 |
| 2         | 3    | コメント2 | 2024-12-02T09:01:05 |

## 複数の行を1つの文字列にまとめる [ STRING_AGG ]

グループ化する時に数値は `MIN` / `MAX` / `AVG` / `SUM` のように集計することが多いですが、文字列の場合はそうもいきません。こうした複数の行を1つの文字列をまとめたい場合には、`STRING_AGG` 関数を使うと便利です。

### データ例

先ほどと同様のレビュー履歴テーブルがあるとします。

| id  | review_id | star | content   | created_at          |
| --- | --------- | ---- | --------- | ------------------- |
| 1   | 1         | 4    | テスト1   | 2024-12-01T00:00:00 |
| 2   | 1         | 3    | テスト2   | 2024-12-01T00:00:01 |
| 3   | 1         | 4    | テスト3   | 2024-12-01T00:00:02 |
| 4   | 2         | 2    | コメント1 | 2024-12-02T09:01:03 |
| 5   | 2         | 3    | コメント2 | 2024-12-02T09:01:05 |

### クエリ

`STRING_AGG` の第2引数には任意の区切り文字を指定できます。以下のクエリは、`review_id` でグループ化し、`star` 列の最小値を取得し、`content` 列をスペース区切りでまとめています。

```sql
SELECT
  review_id,
  MIN(star) AS min_star,
  STRING_AGG(content, ' ') AS all_content,
FROM
  reviews
GROUP BY
  ALL
```

### 出力

| review_id | min_star | all_content             |
| --------- | -------- | ----------------------- |
| 1         | 3        | テスト1 テスト2 テスト3 |
| 2         | 2        | コメント1 コメント1     |

これは特にスプレッドシートの [Connected Sheets](https://cloud.google.com/bigquery/docs/connected-sheets) 機能と合わせ技でよく利用しました。`STRING_AGG(colomn, '\n')` と改行区切りにすることで、複数の行を1つのセルにまとめることができます。

## 行列を入れ替える [ PIVOT ]

データ加工において行と列を入れ替えたい場合、`PIVOT` 演算子を使うと便利です。

### データ例

以下のようにカテゴリー別 × 月別の売上テーブルがあったとします。

| category | month | amount  |
| -------- | ----- | ------- |
| A        | 1     | 100,000 |
| A        | 2     | 110,000 |
| A        | 3     | 120,000 |
| B        | 1     | 330,000 |
| B        | 2     | 350,000 |
| B        | 3     | 370,000 |

### クエリ

行を月単位で揃えて、列をカテゴリーごとに分けたい場合、以下の流れでクエリを記述します。

1. `PIVOT` で集計する値 `amount` を指定
2. `FOR IN` で列を指定
3. 値によって列名を変更したい場合、`AS` でエイリアスを指定

```sql
SELECT
  *
FROM
  sales PIVOT(
    MAX(amount)
    FOR category IN ('A' AS `事業A`, 'B' AS `事業B`)
  )
```

3.がない場合、列名は `category` の値がそのまま列名になります。

### 出力

| month | 事業A   | 事業B   |
| ----- | ------- | ------- |
| 1     | 100,000 | 330,000 |
| 2     | 110,000 | 350,000 |
| 3     | 120,000 | 370,000 |

## まとめ

今回は筆者自身お世話になり、わりと汎用的なBigQueryクエリを3つ紹介しました。たまに公式ドキュメントを見ると新たな発見があって面白いですね。

https://cloud.google.com/bigquery/docs/reference/standard-sql/functions-all
