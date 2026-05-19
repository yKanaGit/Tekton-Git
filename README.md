# Tekton CI/CD Pipeline for Logistics Platform on OpenShift

OpenShift Pipelines (Tekton) を使用して、GitHub からの push イベントで自動的に物流プラットフォームアプリケーション（Shipper Onboarding API）をビルド・デプロイする CI/CD パイプラインです。

## 📦 リポジトリ

https://github.com/yKanaGit/Tekton-Git

## 📋 前提条件

- OpenShift クラスターへのアクセス（OpenShift 4.x 以上）
- OpenShift Pipelines Operator がインストール済み
- `oc` CLI がインストール済み（バージョン確認: `oc version`）
- `tkn` CLI がインストール済み（オプション、パイプライン管理用）
- Git がインストール済み
- **管理者権限または SCC 設定権限**（推奨 - buildah タスクに privileged SCC を付与するため）
  - setup.sh が自動で設定を試みますが、権限がない場合は手動設定が必要です

## 🏗️ アーキテクチャ

```
GitHub Push Event
       ↓
EventListener (Webhook)
       ↓
TriggerBinding + TriggerTemplate
       ↓
PipelineRun
       ↓
┌──────────────────────────────────────┐
│ 1. git-clone                         │
│    - GitHub からソースコードを取得    │
├──────────────────────────────────────┤
│ 2. maven-build                       │
│    - Maven で JAR をビルド           │
├──────────────────────────────────────┤
│ 3. buildah-push                      │
│    - コンテナイメージをビルド＆プッシュ│
├──────────────────────────────────────┤
│ 4. deploy                            │
│    - OpenShift にデプロイ            │
└──────────────────────────────────────┘
```

## 📂 ディレクトリ構成

```
Tekton-Git/
├── app/                    # Shipper Onboarding API (Quarkus)
│   ├── pom.xml
│   └── src/
│       ├── main/
│       │   ├── java/com/example/logistics/
│       │   │   ├── ShipperResource.java
│       │   │   ├── Shipper.java
│       │   │   └── ShipperRepository.java
│       │   ├── resources/
│       │   │   ├── application.properties
│       │   │   └── db/migration/
│       │   └── docker/
│       │       └── Dockerfile.jvm
│       └── test/
├── k8s/                    # OpenShift デプロイメント定義
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── route.yaml
│   ├── postgresql-deployment.yaml
│   └── postgresql-secret.yaml
├── tekton/
│   ├── tasks/              # Tekton タスク定義
│   │   ├── git-clone.yaml
│   │   ├── maven-build.yaml
│   │   ├── buildah-push.yaml
│   │   └── deploy.yaml
│   ├── pipeline/           # パイプライン定義
│   │   └── build-deploy-pipeline.yaml
│   └── triggers/           # Webhook トリガー定義
│       ├── trigger-binding.yaml
│       ├── trigger-template.yaml
│       ├── event-listener.yaml
│       └── event-listener-route.yaml
├── examples/               # サンプルファイル
│   └── pipelinerun-manual.yaml
├── docs/                   # ドキュメント
│   └── RESOURCE_OPTIMIZATION.md
├── setup.sh                # セットアップスクリプト
└── README.md
```

## 🚀 セットアップ手順

**所要時間:** 約10-15分

**手順の流れ:**
1. リポジトリをクローン
2. OpenShift にログイン
3. プロジェクト作成
4. Tekton リソースをデプロイ（setup.sh - SCC 設定も自動試行）
5. SCC 設定の確認（必要に応じて手動設定）
6. Webhook URL の確認
7. GitHub Webhook の設定
8. 動作確認

### 1. リポジトリをクローン

```bash
git clone https://github.com/yKanaGit/Tekton-Git.git
cd Tekton-Git
```

### 2. OpenShift にログイン

```bash
# OpenShift クラスターにログイン
oc login <your-cluster-url>

# ログイン確認
oc whoami
```

### 3. プロジェクト作成（または既存プロジェクトを使用）

```bash
# 新規プロジェクトを作成
oc new-project tekton-demo

# または既存プロジェクトを使用
oc project <your-existing-project>

# 現在のプロジェクトを確認
oc project
```

### 4. Tekton リソースをデプロイ

```bash
# セットアップスクリプトを実行
./setup.sh
```

スクリプトは以下を自動的に実行します：
- ✅ Tekton Task の作成（git-clone, maven-build, buildah-push, deploy）
- ✅ Pipeline の作成（build-deploy-pipeline）
- ✅ Triggers の作成（TriggerBinding, TriggerTemplate, EventListener）
- ✅ Webhook 用の Route 作成（github-webhook）
- ✅ **SCC 設定の自動試行**（管理者権限がある場合）

### 5. SecurityContextConstraints (SCC) の確認（重要！）

**setup.sh は自動的に SCC 設定を試みます**が、管理者権限が必要です。

スクリプト実行時に以下のメッセージが表示された場合は、手動で設定してください：

```
⚠ Could not configure SCC (requires admin privileges)
  Please run manually:
  oc adm policy add-scc-to-user privileged -z pipeline
```

**手動設定コマンド:**

```bash
# pipeline サービスアカウントに privileged SCC を付与
oc adm policy add-scc-to-user privileged -z pipeline

# 確認
oc get scc privileged -o yaml | grep -A 5 users
```

**なぜ必要？**

buildah タスクがコンテナイメージをビルドするために `privileged` 権限が必要です。この設定を省略すると、buildah タスクが以下のエラーで失敗します：

```
PodAdmissionFailed: Privileged containers are not allowed
```

**セキュリティに関する注意:**
- 開発環境・テスト環境では `privileged` SCC で問題ありません
- 本番環境では、より制限的なカスタム SCC の作成を検討してください
- 詳細は `docs/RESOURCE_OPTIMIZATION.md` を参照

### 6. Webhook URL を確認

セットアップ完了後、以下のコマンドで Webhook URL を確認します：

```bash
# Webhook URL を取得
WEBHOOK_URL=$(oc get route github-webhook -o jsonpath='{.spec.host}')
echo "Webhook URL: https://${WEBHOOK_URL}"
```

この URL を次のステップで使用します。

### 7. GitHub Webhook の設定

1. https://github.com/yKanaGit/Tekton-Git/settings/hooks にアクセス
2. **Add webhook** ボタンをクリック
3. 以下を設定：
   - **Payload URL**: `https://<webhook-url>` （Step 5 で取得した URL を入力）
   - **Content type**: `application/json` を選択
   - **Secret**: （オプション、空欄でも可）
   - **SSL verification**: `Enable SSL verification` を選択
   - **Which events would you like to trigger this webhook?**: `Just the push event` を選択
   - **Active**: チェックを入れる
4. **Add webhook** をクリック

設定後、GitHub が Webhook の疎通確認（ping）を送信します。成功すると緑のチェックマークが表示されます。

## 🧪 動作確認

### 方法1: 自動トリガー（推奨）

GitHub に変更をプッシュすると、自動的にパイプラインが実行されます：

```bash
# 簡単な変更を加える
echo "# Test" >> test.txt
git add test.txt
git commit -m "Test webhook trigger"
git push origin main
```

プッシュ後、Tekton パイプラインが自動的に起動します。

### 方法2: 手動でパイプラインを実行

サンプルファイルを使用する場合：

```bash
# サンプルファイルを使用
oc create -f examples/pipelinerun-manual.yaml
```

または、YAML を直接指定：

```bash
oc create -f - <<EOF
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  generateName: build-deploy-run-
spec:
  pipelineRef:
    name: build-deploy-pipeline
  params:
  - name: git-url
    value: https://github.com/yKanaGit/Tekton-Git.git
  - name: git-revision
    value: main
  - name: image-name
    value: image-registry.openshift-image-registry.svc:5000/$(oc project -q)/shipper-onboarding-api
  - name: image-tag
    value: manual-$(date +%Y%m%d-%H%M%S)
  - name: namespace
    value: $(oc project -q)
  workspaces:
  - name: shared-workspace
    volumeClaimTemplate:
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 1Gi
EOF

#### oc CLI を使用

```bash
# PipelineRun 一覧
oc get pipelinerun

# PipelineRun の詳細
oc describe pipelinerun <pipelinerun-name>

# タスクの Pod 一覧
oc get pods | grep build-deploy-run

# 特定の Pod のログ
oc logs <pod-name> -c step-clone  # git-clone ステップ
oc logs <pod-name> -c step-mvn-build  # maven-build ステップ
```

#### OpenShift Console で確認

OpenShift Console にログインして以下にアクセス：
- **Pipelines** > **Pipelines** > **build-deploy-pipeline**
- **PipelineRuns** タブで実行履歴を確認
- 各 PipelineRun をクリックして詳細ログを表示

### アプリケーションへアクセス

デプロイが完了したら、アプリケーションにアクセスできます：

```bash
# Route URL を取得
APP_URL=$(oc get route shipper-onboarding-api -o jsonpath='{.spec.host}')
echo "Application URL: https://${APP_URL}"

# curl でアクセス（ヘルスチェック）
curl https://${APP_URL}/q/health/live

# Shipper API エンドポイント
curl https://${APP_URL}/api/shippers
```

ブラウザで `https://<route-url>/api/shippers` にアクセスして動作を確認できます。

## 🏢 アプリケーション概要

このプロジェクトは、物流プラットフォームの一部である **Shipper Onboarding API** を自動デプロイします。

**主な機能:**
- 運送会社（Shipper）情報の登録・管理
- PostgreSQL データベースとの連携
- Flyway によるデータベースマイグレーション
- RESTful API エンドポイント
- SmallRye Health による健全性チェック

**技術スタック:**
- Quarkus (RESTEasy Reactive, Hibernate ORM with Panache)
- PostgreSQL 15
- Flyway (Database Migration)
- Maven

## 🔧 カスタマイズ

### アプリケーションコードの変更

`app/src/main/java/com/example/logistics/` 配下のファイルを編集して、ビジネスロジックをカスタマイズできます。

### イメージレジストリの変更

デフォルトでは OpenShift 内部レジストリ (`image-registry.openshift-image-registry.svc:5000`) を使用します。
外部レジストリ（Quay.io, Docker Hub など）を使う場合は以下を変更：

1. `tekton/triggers/trigger-template.yaml` の `image-name` パラメータ
2. `k8s/deployment.yaml` の `image` フィールド

### リソース制限の調整

`k8s/deployment.yaml` の `resources` セクションで CPU/メモリの制限を調整できます。

## 📝 トラブルシューティング

### PipelineRun が失敗する

#### 1. ログを確認

```bash
# 最新の PipelineRun のログを確認
tkn pipelinerun logs --last

# 失敗した PipelineRun のログを確認
tkn pipelinerun logs <pipelinerun-name>

# 特定のタスクのログを確認
oc logs <pod-name> -c step-<step-name>
```

#### 2. よくあるエラー

**Maven ビルドが失敗する**
```bash
# Java バージョンの確認
# maven-build タスクで使用している Maven イメージが適切か確認
```

**イメージプッシュが失敗する**
```bash
# OpenShift 内部レジストリへのアクセス権限を確認
oc policy add-role-to-user system:image-builder -z pipeline
```

### EventListener が起動しない

```bash
# EventListener の Pod 状態を確認
oc get pods -l eventlistener=github-listener

# Pod が起動していない場合
oc describe pod -l eventlistener=github-listener

# ログを確認
oc logs -l eventlistener=github-listener

# Service が作成されているか確認
oc get svc el-github-listener

# Route が作成されているか確認
oc get route github-webhook
```

### Webhook が動作しない

#### 1. GitHub 側の確認

https://github.com/yKanaGit/Tekton-Git/settings/hooks にアクセスして：
- Webhook の **Recent Deliveries** タブを確認
- レスポンスが 200 OK になっているか確認
- エラーの場合は詳細を確認

#### 2. EventListener ログを確認

```bash
# EventListener のログをリアルタイム表示
oc logs -l eventlistener=github-listener -f

# Webhook リクエストが届いているか確認
```

#### 3. Route の確認

```bash
# Route が正しく設定されているか
oc get route github-webhook -o yaml

# 外部からアクセス可能か確認
curl -k https://$(oc get route github-webhook -o jsonpath='{.spec.host}')
```

### Buildah でビルドが失敗する

buildah タスクは `privileged: true` が必要です。SecurityContextConstraints (SCC) を確認：

```bash
# pipeline サービスアカウントに privileged SCC を付与
oc adm policy add-scc-to-user privileged -z pipeline

# 確認
oc describe scc privileged | grep Users
```

### デプロイが失敗する

```bash
# Deployment の状態を確認
oc get deployment shipper-onboarding-api

# PostgreSQL の状態を確認
oc get deployment postgresql

# Pod の状態を確認
oc get pods -l app=shipper-onboarding-api
oc get pods -l app=postgresql

# Pod が起動しない場合
oc describe pod -l app=shipper-onboarding-api
oc logs -l app=shipper-onboarding-api

# PostgreSQL ログの確認
oc logs -l app=postgresql

# イメージが正しくプルされているか確認
oc describe deployment shipper-onboarding-api | grep Image
```

### パイプラインを完全にやり直す

```bash
# すべての PipelineRun を削除
oc delete pipelinerun --all

# すべてのリソースを削除して再作成
oc delete -f tekton/tasks/
oc delete -f tekton/pipeline/
oc delete -f tekton/triggers/

# 再度セットアップ
./setup.sh
```

## ❓ よくある質問（FAQ）

### Q1. tkn CLI がない場合はどうすればいいですか？

`oc` CLI だけでもパイプラインを管理できます。または、以下から `tkn` CLI をインストールできます：
- https://tekton.dev/docs/cli/

macOS の場合：
```bash
brew install tektoncd-cli
```

### Q2. OpenShift Pipelines Operator がインストールされているか確認するには？

```bash
oc get pods -n openshift-pipelines
```

Pod が表示されれば Operator がインストール済みです。

### Q3. 別のブランチでパイプラインを実行したい

TriggerTemplate の `git-revision` パラメータを変更するか、手動実行時に指定します：

```bash
oc create -f - <<EOF
# ... (省略)
  - name: git-revision
    value: develop  # ブランチ名を指定
# ... (省略)
EOF
```

### Q4. プライベートリポジトリを使用したい

GitHub プライベートリポジトリの場合、認証情報を含む Secret を作成する必要があります：

```bash
# Personal Access Token を使用
oc create secret generic github-secret \
  --from-literal=username=<your-username> \
  --from-literal=password=<your-token> \
  --type=kubernetes.io/basic-auth

# Secret を pipeline サービスアカウントに紐付け
oc annotate secret github-secret \
  "tekton.dev/git-0=https://github.com"
oc secrets link pipeline github-secret
```

### Q5. ビルド時間を短縮したい

Maven 依存関係のキャッシュを有効にすることで高速化できます：
- PVC を使用して `.m2` ディレクトリをキャッシュ
- Nexus や Artifactory などのリポジトリマネージャーを使用

## 🎯 次のステップ

このパイプラインをさらに拡張するアイデア：

1. **テストの追加**
   - maven-build タスクで `-DskipTests` を外してユニットテストを実行
   - 統合テストタスクを追加

2. **セキュリティスキャン**
   - イメージスキャンタスク（Trivy, Clair など）を追加
   - ソースコード静的解析（SonarQube）を追加

3. **通知の追加**
   - Slack 通知タスクを追加
   - Email 通知を設定

4. **マルチ環境デプロイ**
   - dev, staging, production 環境への段階的デプロイ
   - Approval タスクを追加

5. **モニタリング**
   - Prometheus + Grafana でパイプラインメトリクスを監視
   - アプリケーションログを集約（EFK Stack）

## 📚 参考資料

- [OpenShift Pipelines Documentation](https://docs.openshift.com/pipelines/latest/)
- [Tekton Documentation](https://tekton.dev/docs/)
- [Tekton Catalog](https://hub.tekton.dev/) - 再利用可能なタスク集
- [Quarkus Documentation](https://quarkus.io/guides/)
- [Buildah Documentation](https://buildah.io/)


## 📄 ライセンス

このプロジェクトは MIT ライセンスの下で公開されています。
