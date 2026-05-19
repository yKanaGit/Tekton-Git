# リソース最適化ガイド

## CPU 使用量の目安

### パイプライン全体

| 環境 | CPU 使用量 | 実行時間 | 推奨設定 |
|------|-----------|---------|---------|
| **開発環境** | 2-3 cores | 3-8分 | リソース制限なし |
| **共有環境** | 1-2 cores | 5-15分 | 制限あり（推奨） |
| **本番環境** | 2-4 cores | 3-6分 | 制限あり（必須） |

### タスク別の推奨リソース設定

#### 1. git-clone タスク
```yaml
resources:
  requests:
    memory: "64Mi"
    cpu: "50m"
  limits:
    memory: "128Mi"
    cpu: "200m"
```
- CPU: ほとんど使わない
- 時間: 10-30秒

#### 2. maven-build タスク（最も重い）
```yaml
resources:
  requests:
    memory: "512Mi"
    cpu: "500m"       # 最低 0.5 コア必要
  limits:
    memory: "2Gi"
    cpu: "2000m"      # 最大 2 コアまで使用可
```
- CPU: ビルド中は 1-2 コアを使用
- 時間: 2-5分（初回は依存関係ダウンロードで長い）
- メモリ: 512Mi-2Gi

**Maven の並列ビルドを有効化する場合：**
```yaml
params:
  - name: goals
    value: "clean package -DskipTests -T 2C"  # 2スレッド並列
```
この場合は CPU limits を増やす：
```yaml
limits:
  cpu: "4000m"  # 4 コア
```

#### 3. buildah-push タスク
```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "250m"
  limits:
    memory: "1Gi"
    cpu: "1000m"
```
- CPU: イメージレイヤー圧縮時に使用
- 時間: 1-3分
- メモリ: イメージサイズに依存

#### 4. deploy タスク
```yaml
resources:
  requests:
    memory: "64Mi"
    cpu: "50m"
  limits:
    memory: "256Mi"
    cpu: "500m"
```
- CPU: ほとんど使わない
- 時間: 30秒-1分

## 環境別の推奨設定

### 🟢 開発環境（リソース潤沢）

リソース制限なしで高速ビルド：

```bash
# リソース制限を設定しない
# デフォルトの maven-build.yaml を使用
```

**メリット:** 
- 最速でビルド完了
- シンプルな設定

**デメリット:**
- 他の Pod に影響する可能性

### 🟡 共有環境（推奨）

適度な制限で安定動作：

```bash
# 最適化版のタスクを使用
cp tekton/tasks/maven-build-optimized.yaml tekton/tasks/maven-build.yaml
cp tekton/tasks/buildah-push-optimized.yaml tekton/tasks/buildah-push.yaml
oc apply -f tekton/tasks/
```

**メリット:**
- 他の Pod に影響しない
- 予測可能な実行時間

**デメリット:**
- 少し遅くなる（10-20%程度）

### 🔴 本番環境（厳格）

厳しい制限で安全性重視：

```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "250m"
  limits:
    memory: "1Gi"
    cpu: "500m"     # より低い制限
```

## CPU 使用量を削減する方法

### 1. Maven 依存関係のキャッシュ

PVC を使って `.m2` ディレクトリをキャッシュ：

```yaml
workspaces:
- name: maven-cache
  mountPath: /root/.m2

# Pipeline で workspace を追加
workspaces:
- name: maven-cache
  persistentVolumeClaim:
    claimName: maven-cache-pvc
```

**効果:** 2回目以降のビルドが 50-70% 高速化

### 2. ビルド頻度の調整

- **main ブランチのみ**: webhook を main のみに設定
- **手動トリガー**: 自動 webhook を無効化

### 3. 並列ビルドの制御

OpenShift の Quota で同時実行数を制限：

```bash
# 同時に実行できる Pod 数を制限
oc create quota pipeline-quota \
  --hard=pods=5,cpu=4,memory=8Gi
```

### 4. テストのスキップ

現在は `-DskipTests` でスキップ済み。

テストを実行する場合は CPU を増やす：
```yaml
limits:
  cpu: "3000m"  # 3 コア
```

## モニタリング

### パイプライン実行中の CPU 使用量を確認

```bash
# リアルタイムで Pod のリソース使用量を確認
oc adm top pods -l tekton.dev/pipelineRun

# 特定の Pod の詳細
oc adm top pod <pod-name>

# 履歴データ（Prometheus が必要）
# OpenShift Console > Observe > Metrics
```

### パイプライン実行時間の計測

```bash
# PipelineRun の実行時間を確認
tkn pipelinerun describe <pipelinerun-name> | grep Duration

# 全 PipelineRun の統計
tkn pipelinerun list -o json | jq '.items[] | {name: .metadata.name, duration: .status.completionTime}'
```

## トラブルシューティング

### CPU 制限が厳しすぎる場合

**症状:** ビルドが異常に遅い、タイムアウトする

```bash
# タスクの CPU 使用状況を確認
oc adm top pod <maven-build-pod>

# CPU が limits に張り付いている場合は制限を緩和
```

### メモリ不足エラー

**症状:** OOMKilled、Java heap space エラー

```bash
# メモリ制限を増やす
resources:
  limits:
    memory: "3Gi"  # 2Gi → 3Gi

# または Maven のヒープを減らす
export MAVEN_OPTS="-Xmx1024m"  # 1536m → 1024m
```

### Pod が起動しない

**症状:** Insufficient cpu, Insufficient memory

```bash
# クラスター全体のリソースを確認
oc describe node | grep -A 5 "Allocated resources"

# requests を下げる
resources:
  requests:
    cpu: "250m"  # 500m → 250m
```

## ベンチマーク例

小規模 Quarkus アプリでの実測値（OpenShift 4.x）：

| タスク | CPU (avg) | CPU (peak) | メモリ (avg) | 時間 |
|--------|-----------|-----------|-------------|------|
| git-clone | 0.05 cores | 0.15 cores | 30Mi | 15秒 |
| maven-build (初回) | 1.2 cores | 1.8 cores | 1.2Gi | 4分30秒 |
| maven-build (キャッシュ有) | 0.8 cores | 1.5 cores | 800Mi | 1分45秒 |
| buildah-push | 0.4 cores | 0.9 cores | 450Mi | 2分10秒 |
| deploy | 0.05 cores | 0.2 cores | 50Mi | 35秒 |

**合計:** ~8分30秒（初回）、~5分（キャッシュ有）
