# Tekton CI/CD Pipeline for Quarkus on OpenShift

OpenShift Pipelines (Tekton) を使用して、GitHub からの push イベントで自動的に Quarkus アプリケーションをビルド・デプロイする CI/CD パイプラインです。

## 📋 前提条件

- OpenShift クラスターへのアクセス（OpenShift 4.x 以上）
- OpenShift Pipelines Operator がインストール済み
- `oc` CLI がインストール済み
- GitHub リポジトリ

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
├── setup.sh                # セットアップスクリプト
└── README.md
```

## 🚀 セットアップ手順

### 1. OpenShift にログイン

```bash
oc login <cluster-url>
```

### 2. プロジェクト作成（または既存プロジェクトを使用）

```bash
oc new-project tekton-demo
# または
oc project <your-project>
```

### 3. Tekton リソースをデプロイ

```bash
chmod +x setup.sh
./setup.sh
```

スクリプトは以下を実行します：
- Tekton Task の作成
- Pipeline の作成
- Triggers（TriggerBinding, TriggerTemplate, EventListener）の作成
- Webhook 用の Route 作成

### 4. Webhook URL を取得

```bash
oc get route github-webhook -o jsonpath='{.spec.host}'
```

### 5. GitHub Webhook の設定

1. GitHub リポジトリの **Settings** > **Webhooks** > **Add webhook**
2. 以下を設定：
   - **Payload URL**: `https://<webhook-url>` （Step 4 で取得した URL）
   - **Content type**: `application/json`
   - **Secret**: （オプション）
   - **Which events**: `Just the push event`
3. **Add webhook** をクリック

## 🧪 動作確認

### 手動でパイプラインを実行

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
    value: https://github.com/YOUR_USERNAME/YOUR_REPO.git
  - name: git-revision
    value: main
  - name: image-name
    value: image-registry.openshift-image-registry.svc:5000/$(oc project -q)/quarkus-demo
  - name: image-tag
    value: manual-test
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

```bash
# PipelineRun 一覧
tkn pipelinerun list

# ログをリアルタイム表示
tkn pipelinerun logs -f <pipelinerun-name>

# OpenShift Console でも確認可能
# Pipelines > Pipelines > build-deploy-pipeline
```

### アプリケーションへアクセス

```bash
# Route URL を取得
oc get route quarkus-demo -o jsonpath='{.spec.host}'

# ブラウザまたは curl でアクセス
curl https://<route-url>/hello
# 出力: Hello from Quarkus on OpenShift!
```

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

```bash
# 詳細ログを確認
tkn pipelinerun logs <pipelinerun-name>

# 特定のタスクのログを確認
oc logs <pod-name> -c step-<step-name>
```

### EventListener が起動しない

```bash
# EventListener の Pod 状態を確認
oc get pods -l eventlistener=github-listener

# ログを確認
oc logs -l eventlistener=github-listener
```

### Buildah でビルドが失敗する

buildah タスクは `privileged: true` が必要です。SecurityContextConstraints (SCC) を確認：

```bash
oc adm policy add-scc-to-user privileged -z pipeline
```

## 📚 参考資料

- [OpenShift Pipelines Documentation](https://docs.openshift.com/pipelines/latest/)
- [Tekton Documentation](https://tekton.dev/docs/)
- [Quarkus Documentation](https://quarkus.io/guides/)

## 📄 ライセンス

このプロジェクトは MIT ライセンスの下で公開されています。
