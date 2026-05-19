# Tekton CI/CD Pipeline for Quarkus on OpenShift

OpenShift Pipelines (Tekton) を使用して、GitHub からの push イベントで自動的に Quarkus アプリケーションをビルド・デプロイする CI/CD パイプラインです。

## 📦 リポジトリ

https://github.com/yKanaGit/Tekton-Git

## 📋 前提条件

- OpenShift クラスターへのアクセス（OpenShift 4.x 以上）
- OpenShift Pipelines Operator がインストール済み
- `oc` CLI がインストール済み（バージョン確認: `oc version`）
- `tkn` CLI がインストール済み（オプション、パイプライン管理用）
- Git がインストール済み

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
├── app/                    # Quarkus アプリケーション
│   ├── pom.xml
│   └── src/
│       ├── main/
│       │   ├── java/com/example/demo/
│       │   │   └── GreetingResource.java
│       │   ├── resources/
│       │   └── docker/
│       │       └── Dockerfile.jvm
│       └── test/
├── k8s/                    # OpenShift デプロイメント定義
│   ├── deployment.yaml
│   ├── service.yaml
│   └── route.yaml
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

### 5. Webhook URL を確認

セットアップ完了後、以下のコマンドで Webhook URL を確認します：

```bash
# Webhook URL を取得
WEBHOOK_URL=$(oc get route github-webhook -o jsonpath='{.spec.host}')
echo "Webhook URL: https://${WEBHOOK_URL}"
```

この URL を次のステップで使用します。

### 6. GitHub Webhook の設定

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
    value: image-registry.openshift-image-registry.svc:5000/$(oc project -q)/quarkus-demo
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
```

### パイプライン実行状況の確認

#### tkn CLI を使用（推奨）

```bash
# PipelineRun 一覧を表示
tkn pipelinerun list

# 最新の PipelineRun のログをリアルタイム表示
tkn pipelinerun logs -f --last

# 特定の PipelineRun のログを表示
tkn pipelinerun logs -f <pipelinerun-name>

# PipelineRun の詳細を表示
tkn pipelinerun describe <pipelinerun-name>
```

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
APP_URL=$(oc get route quarkus-demo -o jsonpath='{.spec.host}')
echo "Application URL: https://${APP_URL}"

# curl でアクセス
curl https://${APP_URL}/hello

# 期待される出力
# Hello from Quarkus on OpenShift!
```

ブラウザで `https://<route-url>/hello` にアクセスして動作を確認できます。

## 🔧 カスタマイズ

### アプリケーションコードの変更

`app/src/main/java/com/example/demo/GreetingResource.java` を編集して、レスポンスをカスタマイズできます。

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
oc get deployment quarkus-demo

# Pod の状態を確認
oc get pods -l app=quarkus-demo

# Pod が起動しない場合
oc describe pod -l app=quarkus-demo
oc logs -l app=quarkus-demo

# イメージが正しくプルされているか確認
oc describe deployment quarkus-demo | grep Image
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

## 🤝 コントリビューション

このリポジトリへの改善提案や Pull Request を歓迎します！

1. このリポジトリをフォーク
2. フィーチャーブランチを作成 (`git checkout -b feature/amazing-feature`)
3. 変更をコミット (`git commit -m 'Add some amazing feature'`)
4. ブランチにプッシュ (`git push origin feature/amazing-feature`)
5. Pull Request を作成

## 📄 ライセンス

このプロジェクトは MIT ライセンスの下で公開されています。
