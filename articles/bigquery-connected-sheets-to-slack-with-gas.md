---
title: "BigQuery 実行結果の可変な行数を Slack に定期投稿する"
emoji: "🔍"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["bigquery", "googlesheets", "slack", "gas"]
publication_name: "zozotech"
published: true
published_at: 2023-12-02 00:00
---

:::message
本記事は、[ZOZO Advent Calendar 2023](https://qiita.com/advent-calendar/2023/zozo) シリーズ9の2日目の記事です。
:::

## はじめに

BigQueryのクエリ結果を定期的にSlack投稿するソリューションは様々あります。
特に、固定行数を投稿する場合は、ノーコードで簡単に実現できるでしょう。

https://techblog.zozo.com/entry/bq-to-slack-with-nocode

一方で、実行タイミングによって可変な行数を投稿する場合は、GASで多少のローコードが必要になってきます。
本記事ではこうしたケースでも、できるだけ最小限の労力で実現するためのソリューションを紹介していきます。また、サービスとしての制約がいくつかあるため、ハマるポイントも合わせて解説していきます。

## システム構成

システム構成は以下の通りです。詳しくは次章以降で解説していきます。

![architecture](/images/articles/bigquery-connected-sheets-to-slack-with-gas/architecture.drawio.png)

- データ取得
  - BigQueryから対象データを取得する処理は、`Connected Sheets`を利用してGoogle Sheetsに出力します。
- メッセージ投稿
  - 取得したデータを読み込み、Slackメッセージとして編集・送信する処理は、`Google Apps Script`を利用します。
  - Slackでメッセージを受信する処理は、`Workflow Builder`を利用します。

## Connected Sheets

まずは、BigQueryからのデータ取得には、`Connected Sheets`を利用します。
これにより、BigQueryの実行結果をGoogle Sheets（スプレッドシート）に簡単に出力できます。

https://cloud.google.com/bigquery/docs/connected-sheets

また、スケジュールされた更新オプションにより、定期的にデータを更新できます。
ただし、Connected Sheetsの定期実行はいくつかサービスとしての制約がある点に注意が必要です。

- 設定は1時間単位の`レンジ`で指定する必要がある
- 定期間隔で実行されない

例えば、以下のようにスケジュール指定してクエリを実行したとします。

<!-- textlint-disable -->

![connected-sheets-schedule](/images/articles/bigquery-connected-sheets-to-slack-with-gas/connected-sheets-schedule.png =400x)
_Connected Sheetsスケジュール設定_

<!-- textlint-enable -->

```sql
-- 現在時刻から過去4時間分のデータを取得する
DECLARE now TIMESTAMP;
SET now = CURRENT_TIMESTAMP();

SELECT
  FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S', created_at, 'Asia/Tokyo') AS created_at,
  message,
FROM
  `project.dataset.table`
WHERE
  created_at BETWEEN TIMESTAMP_SUB(now, INTERVAL 4 HOUR) AND now
ORDER BY
  created_at
```

この場合、実際のスケジュール実行時間は以下のようになりました。

- 1回目: 11/30 17:15
- 2回目: 11/30 21:46
- 3回目: 12/1 1:30
- 4回目: 12/1 5:30
- 5回目: 12/1 9:10
- 6回目: 12/1 13:55
- 7回目: 12/1 17:55

そのため、以下のような条件でクエリを実行していたことになるため、**データの重複や欠落が発生**しています。

![connected-sheets-window](/images/articles/bigquery-connected-sheets-to-slack-with-gas/connected-sheets-window.drawio.png)

このような制約が許容できる場合、もしくは無視できるクエリ内容の場合に限り、定期的なBigQueryデータ取得としてConnected Sheetsは最も簡単な手法になるでしょう。

## Slack Workflow Builder

次に、Slack投稿する処理を実装する前に、先にSlack側でメッセージを受信する受け口を作成していきます。
これは、`Incoming Webhook`を利用して実装もできますが、今回はより簡単に実装できる`Workflow Builder`を利用します。

Workflow Builderは、端的に言えばiPaaSのひとつで、様々なアクションをワークフロー化して実行できる機能です。また、定義したワークフローをWebhookで実行できます。

https://slack.com/intl/ja-jp/help/articles/360041352714-%E3%83%AF%E3%83%BC%E3%82%AF%E3%83%95%E3%83%AD%E3%83%BC%E3%82%92%E4%BD%9C%E6%88%90%E3%81%99%E3%82%8B---Slack-%E5%A4%96%E9%83%A8%E3%81%A7%E9%96%8B%E5%A7%8B%E3%81%95%E3%82%8C%E3%82%8B%E3%83%AF%E3%83%BC%E3%82%AF%E3%83%95%E3%83%AD%E3%83%BC%E3%82%92%E4%BD%9C%E6%88%90%E3%81%99%E3%82%8B

今回は作成日時とメッセージを受け取って、Slackにメッセージを送信するワークフローを作成したいので、以下のように設定します。

<!-- textlint-disable -->

![workflow-builder-webhook](/images/articles/bigquery-connected-sheets-to-slack-with-gas/workflow-builder-webhook.png =400x)
_Workflow Builder Webhook設定_

<!-- textlint-enable -->

こうすることでWebhook URLが発行され、以下のようなJSON形式でPOSTすることによって、Slack Workflow Builderで定義したワークフローが実行できるようになります。

```json
{
  "created_at": "2021-11-30 17:00:00",
  "message": "Hello World!"
}
```

さて、次にWebhookで呼ばれた後、受信したメッセージを元にSlackチャンネルへ投稿するワークフローを作成します。これは、Workflow Builder上のGUI操作で完結します。

<!-- textlint-disable -->

![workflow-builder-webhook](/images/articles/bigquery-connected-sheets-to-slack-with-gas/workflow-builder-setting.png =800x)
_Workflow Builder ワークフロー設定_

<!-- textlint-enable -->

これで、Workflow Builderの設定は完了です。
試しに以下のようなリクエストを送信してみると、Slackチャンネルにメッセージ投稿されることが確認できます。

```bash
$ curl -X POST https://hooks.slack.com/triggers/xxxxx \
  -H "Content-Type: application/json" \
  -d '{"created_at": "2021-11-30 17:00:00", "message": "Hello World!"}'

{"ok":true}
```

<!-- textlint-disable -->

![workflow-builder-webhook](/images/articles/bigquery-connected-sheets-to-slack-with-gas/slack-message.png =800x)
_メッセージ投稿結果_

<!-- textlint-enable -->

## Google Apps Script

次に、Connected Sheetsで出力したデータを読み込み、前述のSlack Workflow Builderにメッセージ送信する処理をGASで実装していきます。
この時、固定行数であれば`Slack Workflow Builder`だけで完結するのですが、今回は過去4時間分のデータを取得しているため、行数が可変になります。これは、GASで実装する必要がありますが、そこまで難しい実装ではありません。

以下に実装例を示します。

```js
function sendRowsToSlackApi() {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName("Sheet1");
  const range = sheet.getDataRange();
  const values = range.getValues();

  // 1行目のヘッダ部を削除
  values.shift();

  // 2行目以降のデータをSlackに送信
  for (const row of values) {
    const [createdAt, message] = row; // 1行分のデータを列単位で変数に格納

    const data = {
      created_at: createdAt,
      message,
    };

    const options = {
      method: "post",
      contentType: "application/json",
      payload: JSON.stringify(data),
    };

    const apiEndpoint = "https://hooks.slack.com/triggers/xxxxx";

    try {
      var response = UrlFetchApp.fetch(apiEndpoint, options);
      Logger.log(response.getContentText());
    } catch (error) {
      Logger.log(error);
    }
  }
}
```

今回は1行ごとに1メッセージを送信する処理を実装していますが、場合によって複数行を1メッセージにまとめて送信もできます。

最後に、GASのトリガーを設定して、上述のスクリプトを定期実行するようにします。
これは、スクリプトエディタの`トリガー`から設定できます。

<!-- textlint-disable -->

![gas-schedule](/images/articles/bigquery-connected-sheets-to-slack-with-gas/gas-schedule.png =500x)
_GASスケジュール設定_

<!-- textlint-enable -->

ただし、GASの定期実行に関しても、いくつかサービスとしての制約がある点に注意が必要です。

- 指定した間隔で定期実行されるが、最大15分のズレが発生する[^gas-15-minutes]
- 開始時刻が選択できない（設定した時刻 = 開始時刻）

[^gas-15-minutes]:
    Specifies the minute at which the trigger runs (plus or minus 15 minutes).
    https://developers.google.com/apps-script/reference/script/clock-trigger-builder#nearminuteminute

もし、クエリが実行された後にできるだけ早くSlack投稿したい場合、GASトリガーをConnected Sheetsの実行幅の終了時刻+16分に設定することで実現できます。例えば、以下のように設定することで、クエリ実行 → Slack投稿の間の待機時間が（およそ）`最大91分`になります。

- Connected Sheets
  - 17:00~18:00
- GAS
  - 18:16（18:01~18:31の間に実行される）

ただ、これでは実行猶予のない設計になるので、GAS実行時刻はConnected Sheetsの実行幅の終了時刻+30分（待機時間は`最大105分`）に設定しておくのが現実的なところでしょう。

## まとめ

今回は、BigQueryの実行結果（可変行数）をSlackに定期投稿するソリューションを、できるだけ最小限の労力で実現する方法を紹介しました。

ただし、以下のような点に注意が必要です。

- サービス間の実行制御は時刻でしか制御していない（直列実行ではない）
- クエリの内容によっては実行時刻にズレが発生するため、データ重複・欠落の可能性がある

こうしたデメリットがあるため、厳密なデータ取得をする場合には不向きですが、ローコードで手早く作れる点にメリットがあります。

ざっくりとしたデータを定期的に通知するソリューションとして構築してみて、芽があればより厳密な実装に切り替えていく、といったファーストステップとしては良いのではないでしょうか。
