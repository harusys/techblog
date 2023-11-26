---
title: "Scheduler + Pub/Sub + Cloud Functions を Terraform でイイ感じに管理する"
emoji: "❄️"
type: "tech" # tech: 技術記事 / idea: アイデア
topics:
  ["googlecloud", "cloudscheduler", "pubsub", "cloudfunctions", "terraform"]
publication_name: "zozotech"
published: true
published_at: 2023-12-03 00:00
---

## はじめに

Cloud Functionsで軽量なバッチシステムを構築していたところ、システムを構成するリソースが多く、手動管理に限界を感じてTerraformを導入しました。
Google Cloud公式チュートリアルを参考に導入したものの、あくまでチュートリアルなので、実用面でそのまま使うには不便な点がいくつかありました。

そこで本記事では、公式チュートリアルをより実践的なTerraformコードに育てるポイントをいくつか紹介します。

## 実行環境

- macOS Ventura 13.6.2
- Terraform v1.6.4
- Cloud Functions 2nd Gen

## システム構成

主なリソースおよび最終的なシステム構成は以下の通りです。

| リソース名      | 用途                                            |
| --------------- | ----------------------------------------------- |
| Cloud Scheduler | 定期的なイベント実行管理                        |
| Pub/Sub         | イベント受信・送信                              |
| Cloud Functions | アプリケーション実行環境                        |
| Secret Manager  | シークレット管理                                |
| Cloud Storage   | ソースコード置き場（Cloud Functionsデプロイ用） |
| Terraform Cloud | Terraform実行環境・ステート管理                 |

![architecture](/images/articles/scheduler-pubsub-cloud-function-terraform/architecture.drawio.png)

https://cloud.google.com/functions/docs/deploy#from-cloud-storage

:::message
※1:
実際には、Cloud BuildからCloud Functionsにデプロイされますが、この辺りの構築プロセスはユーザーが意識する必要のない作りになっています。
Cloud Functionsのデプロイにはいくつか手法がありますが、代表的な「Cloud Storageからデプロイ」の場合、実際には以下のプロセスで動作をしています。

1. Cloud Storageにあるzipファイルを取得する
2. zipファイルを解凍して、Cloud Build上でビルド -> コンテナイメージを作成する
3. 2.で作成したコンテナイメージを、Artifact Registryにpushして保存する
4. Cloud Functionsは、3.で保存したコンテナイメージをpullして実行する

ただ、これらの過程はTerraformコードにも登場しないので、今回の焦点に絞って「Cloud Storage -> Cloud Functionsにデプロイ」と表現している点に注意が必要です。

:::

## テンプレート

https://cloud.google.com/functions/docs/tutorials/terraform-pubsub

はじめに、Google Cloud公式チュートリアルで出来ることを確認しておきます。
また、以降は公式チュートリアルのTerraformコードを「テンプレート」と呼称します。

1. `google_service_account`
   - Cloud Functions用のサービスアカウントを作成する
2. `google_pubsub_topic`
   - Pub/Subリソースを作成する
3. `google_storage_bucket`
   - Cloud Functionsデプロイ用のストレージを作成する
4. `archive_file`
   - Terraform実行環境上でソースコードをzip化する
5. `google_storage_bucket_object`
   - zip化したソースコードをCloud Storageにアップロードする
6. `google_cloudfunctions_function`
   - Cloud Functionsリソースを作成する

前述のシステム構成にテンプレートのカバー範囲をマッピングすると以下の通りです。

![architecture](/images/articles/scheduler-pubsub-cloud-function-terraform/template-cover.drawio.png)

## ポイント

### Cloud Schedulerを同時にデプロイする

https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_scheduler_job

テンプレートは、汎用的なPub/Subトリガーのサンプルであり、Cloud Schedulerが含まれていない（必要ないユースケースがある）ため、追加したいです。
これは`google_cloud_scheduler_job`リソースを追加するだけで簡単に実現できます。

```diff ruby
+resource "google_cloud_scheduler_job" "default" {
+  name      = "scheduler"
+  schedule  = "0 0 * * *" # 毎日0時(JST)に実行
+  time_zone = "Asia/Tokyo"
+
+  pubsub_target {
+    topic_name = google_pubsub_topic.default.id
+    data       = "{\"name\": \"Haru\"}"
+  }
+}
```

### 機密情報はSecret Managerで管理する

https://cloud.google.com/functions/docs/configuring/secrets

Cloud Functionsに限った話ではありませんが、環境変数は機密情報の格納先に適していません。[^env-var]
そのため、機密情報はSecret Managerで管理するようテンプレートを変更したいです。

これを実現する詳細な手順は上記のドキュメントに記載されていますが、ここではTerraformを用いて実行していきます。
ただし、1.のシークレット保存については機密情報の取り扱いが厄介なので、ここでは手動で登録することとします。

1. Secret Managerにシークレットを保存する。（手動）
2. Cloud Functions用サービスアカウントに `secretmanager.secretAccessor` ロールを付与する。
3. Cloud Functionsからシークレットを参照する。

```diff ruby
+# Cloud Functions用サービスアカウントにシークレットアクセス権限を付与する
+resource "google_project_iam_member" "secret_accessor" {
+  project = "project_id"
+  role    = "roles/secretmanager.secretAccessor"
+  member  = "serviceAccount:${google_service_account.default.email}"
+}

resource "google_cloudfunctions2_function" "default" {
  service_config {
+    # Secret Manager参照先を指定する
+    secret_environment_variables {
+      key        = "SECRET_CONFIG_TEST" # 環境変数名
+      project_id = "project_id"
+      secret     = "SECRET_NAME"        # Secret Managerに登録したシークレット名
+      version    = "1"                  # シークレットのバージョン
+    }
  }
}
```

[^env-var]:
    環境変数は関数の構成に使用できますが、データベースの認証情報やAPIキーなどの機密情報の格納には適しません。 このような機密性の高い値は、ソースコードや外部の環境変数以外の場所に保存する必要があります。
    (中略)
    シークレットを保存するには、Secret Managerを使用することをおすすめします。
    https://cloud.google.com/functions/docs/configuring/env-var#managing_secrets

### ソースコードの変更を検知する

https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle

テンプレートのままでは、ソースコードのみ変更した場合、Cloud Storageの再アップロードは発生しますが、Cloud Functionsの再デプロイまでは行われません。[^no-changes]
そのため、ソースコードが変わる（つまり、Cloud Storageにアップロードするzipファイルが置き換わる）と、それを検知して再デプロイするように変更したいです。

これはTerraformの`lifecycle`メタ引数を用いることで簡単に実現できます。

```diff ruby
resource "google_cloudfunctions2_function" "default" {
+  # Google Storageにアップロードしたzipファイルの変更を検知する
+  lifecycle {
+    replace_triggered_by = [
+      google_storage_bucket_object.default
+    ]
+  }
}
```

[^no-changes]:
    Updating Cloud Functions' source code requires changing zip path
    https://github.com/hashicorp/terraform-provider-google/issues/1938#issuecomment-1229042663

### 不要ファイルをデプロイしない

https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file

テンプレートの`archive_file`リソースは、指定したフォルダ配下のすべてのファイルをzip化します。
しかし、ソースコードの中には、`.env`やテスト用コードなどが含まれるため、これらの不要ファイルはデプロイしないように変更したいです。

これは `excludes` パラメータで簡単に実現できるのですが、残念ながらファイル単位かつ、ワイルドカードが使えません。
長らく要望はIssueに挙がっていますが未だに対応されておらず、ファイル数が多い場合はコメントで提案されているような対応が必要になります。[^excludes]

ここでは、最低限の対応として`.env`ファイルのみを除外しておきます。

```diff ruby
data "archive_file" "default" {
  type        = "zip"
  output_path = "/tmp/function-source.zip"
  source_dir  = "function-source/"
+  # 除外したいファイルを指定する
+  excludes = [
+    ".env",
+  ]
}
```

[^excludes]:
    Support glob paths in archive_file data source excludes
    https://github.com/hashicorp/terraform-provider-archive/issues/62

## まとめ

https://github.com/harusys/techblog/tree/main/samples/scheduler-pubsub-cloud-function-terraform/terraform

最終的にできたTerraformコードはこちらになります。
本記事での主軸ではないので割愛していますが、同じ構成のバッチシステムが増えた時に再利用しやすいよう、変数ファイルは分離しています。

以下の手順に沿って実行すると、テンプレートを基にカスタマイズTerraformコードが実行できます。

1. `terraform/main.tf`を編集する
2. `gcloud auth application-default login`で認証をする
3. `terraform`コマンド実行

ただし、現状ではTerraform実行・ステート管理がローカル依存となっているので、実際にチームで運用する場合には、以下のような対応が追加で必要になります。この辺りは長くなってきたので、また別の記事でぼちぼち書いていきます。

- Terraform Cloudを導入する
- ステートをCloud Storageに保存する + 実行はサービスアカウントを利用する

最後になりますが、Terraformコードの書き方に悩んだ際には、Google Cloud公式がガイドラインを出してくれていますので、参考にしてみてください。

https://cloud.google.com/docs/terraform/best-practices-for-terraform
