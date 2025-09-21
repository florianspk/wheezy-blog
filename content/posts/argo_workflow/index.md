---
title: "Argo Workflows : orchestrer vos jobs Kubernetes comme un pro"
date: 2025-09-19
summary: "Introduction complète à Argo Workflows avec un exemple simple et reproductible"
tags: ["Kubernetes", "GitOps", "DevOps", "Argo"]
categories: ["Automation"]
featuredImage: "featured.png"
---

# Introduction

## 🎯 Pourquoi Argo Workflows ?

Dans le monde Kubernetes, automatiser des processus complexes est un véritable défi.
Que ce soit pour :
- Des **pipelines CI/CD**
- Des **jobs de traitement de données**
- Du **Machine Learning**
- Ou la **migration d'applications legacy**

On a besoin d'une solution capable de **définir, planifier et exécuter des workflows complexes** directement dans Kubernetes.

C'est exactement ce que fait **Argo Workflows**.
C'est un **orchestrateur Kubernetes-native**, conçu pour décomposer vos jobs en **étapes (steps)**, connectées entre elles, le tout décrit en YAML.

En d'autres termes :
- 📝 Définition déclarative → 100% GitOps-friendly
- ⚡ Scalabilité native grâce à Kubernetes
- 🔗 Intégration parfaite avec le reste de la suite Argo (Events, CD)

---

## 🧩 Architecture d'Argo Workflows

Argo Workflows s'appuie sur plusieurs CRDs Kubernetes :

| **Composant**       | **Rôle** |
|---------------------|----------|
| **Workflow**        | La ressource principale : décrit le pipeline à exécuter |
| **WorkflowTemplate**| Template réutilisable de workflow |
| **CronWorkflow**    | Pour exécuter un workflow selon un horaire |
| **WorkflowController** | Le contrôleur qui orchestre l'exécution des workflows |

💡 **Concept clé** : chaque étape d'un workflow est exécutée dans un **Pod Kubernetes**, ce qui permet une isolation forte et une scalabilité parfaite.


<div style="display: flex; gap: 20px; justify-content: space-around; align-items: flex-start; flex-wrap: wrap;">

<div style="flex: 1; min-width: 300px; text-align: center;">

### Workflow simple
{{< mermaid >}}
flowchart TD
    A[Start] --> B[Step 1 : Extract data]
    B --> C[Step 2 : Transform data]
    C --> D[Step 3 : Load to Database]
    D --> E[End]
{{< /mermaid >}}

</div>

<div style="flex: 1; min-width: 300px; text-align: center;">

### Workflow DAG
{{< mermaid >}}
flowchart TD
    A[Start] --> B[Step 1 : Fetch raw data]
    B --> C[Step 2A : Clean data]
    B --> D[Step 2B : Generate metadata]
    C --> E[Step 3 : Aggregate & validate]
    D --> E
    E --> F[Step 4 : Load to production DB]
    F --> G[End]
{{< /mermaid >}}

</div>

</div>






---

# ⚙️ Installation

> **Pré-requis** : un cluster Kubernetes fonctionnel et `kubectl`.

1. **Créer un namespace dédié**
{{< highlight bash >}}
kubectl create namespace argo-workflows
{{< /highlight >}}


2. **Installer Argo Workflows**
{{< highlight bash >}}
kubectl apply -n argo-workflows -f https://raw.githubusercontent.com/argoproj/argo-workflows/stable/manifests/quick-start-minimal.yaml
{{< /highlight >}}


3. **Vérifier que tout est OK**
{{< highlight bash >}}
kubectl get pods -n argo-workflows
{{< /highlight >}}


Vous devriez voir :
```
workflow-controller-xxxx    Running
argo-server-xxxx            Running
```

---

# 🎬 Exemple live : workflow basique

Objectif de la démo :
- Définir un workflow qui exécute **deux étapes successives** :
  1. Afficher "Hello"
  2. Afficher "World"

---

## Créer le Workflow

{{< highlight yaml >}}
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: data-pipeline-dag-
spec:
  entrypoint: data-pipeline-dag
  templates:
  - name: data-pipeline-dag
    dag:
      tasks:
      - name: fetch-data
        template: fetch-data

      - name: clean-data
        dependencies: [fetch-data]
        template: clean-data

      - name: generate-metadata
        dependencies: [fetch-data]
        template: generate-metadata

      - name: aggregate-validate
        dependencies: [clean-data, generate-metadata]
        template: aggregate-validate

      - name: load-production
        dependencies: [aggregate-validate]
        template: load-production

  # --- Templates (containers exécutés) ---
  - name: fetch-data
    container:
      image: alpine:3.20
      command: [sh, -c]
      args: ["echo '📥 Fetching raw data...' && sleep 2"]

  - name: clean-data
    container:
      image: alpine:3.20
      command: [sh, -c]
      args: ["echo '🧹 Cleaning data...' && sleep 3"]

  - name: generate-metadata
    container:
      image: alpine:3.20
      command: [sh, -c]
      args: ["echo '📝 Generating metadata...' && sleep 2"]

  - name: aggregate-validate
    container:
      image: alpine:3.20
      command: [sh, -c]
      args: ["echo '🔗 Aggregating and validating data...' && sleep 4"]

  - name: load-production
    container:
      image: alpine:3.20
      command: [sh, -c]
      args: ["echo '🚀 Loading data to production DB...' && sleep 2"]
{{< /highlight >}}


Appliquer le workflow :
{{< highlight yaml >}}
kubectl create -f data-pipeline-dag.yaml
{{< /highlight >}}


Lister les workflows :
{{< highlight bash >}}
kubectl get wf -n argo-workflows
{{< /highlight >}}


🎉 Votre premier workflow Kubernetes est opérationnel !

---

# ⏰ Déclencher un workflow à intervalles réguliers

Argo Workflows propose aussi les **CronWorkflows**, pour planifier l'exécution de workflows.

```yaml
# cron-hello-world.yaml
apiVersion: argoproj.io/v1alpha1
kind: CronWorkflow
metadata:
  name: cron-hello-world
  namespace: argo-workflows
spec:
  schedule: "*/5 * * * *" # toutes les 5 minutes
  workflowSpec:
    entrypoint: main
    templates:
    - name: main
      container:
        image: alpine:3.18
        command: [echo]
        args: ["Hello every 5 minutes!"]
```

Appliquer :
```bash
kubectl apply -f cron-hello-world.yaml
```

Vérifier le déclenchement automatique :
```bash
kubectl get wf -n argo-workflows
```

---

# 📦 Les Artefacts : partager des données entre étapes

Les **artefacts** sont l'un des concepts les plus puissants d'Argo Workflows. Ils permettent de **partager des fichiers et données** entre différentes étapes du workflow, créant ainsi de véritables pipelines de données.

## 🔧 Comment ça fonctionne ?

Un artefact peut être :
- **Produit** par une étape (output)
- **Consommé** par une autre étape (input)
- **Stocké** dans différents backends (S3, GCS, Azure, etc.)

### Exemple : Pipeline avec artefacts

{{< highlight yaml >}}
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: artifacts-pipeline-
spec:
  entrypoint: artifact-pipeline
  templates:
  - name: artifact-pipeline
    dag:
      tasks:
      - name: generate-data
        template: data-generator

      - name: process-data
        dependencies: [generate-data]
        template: data-processor
        arguments:
          artifacts:
          - name: input-data
            from: "{{tasks.generate-data.outputs.artifacts.raw-data}}"

      - name: analyze-results
        dependencies: [process-data]
        template: data-analyzer
        arguments:
          artifacts:
          - name: processed-data
            from: "{{tasks.process-data.outputs.artifacts.clean-data}}"

  # --- Générateur de données ---
  - name: data-generator
    container:
      image: alpine:3.20
      command: [sh, -c]
      args: |
        - echo "🔧 Generating raw data..."
        - mkdir -p /tmp/output
        - echo "user1,25,engineer" > /tmp/output/data.csv
        - echo "user2,30,designer" >> /tmp/output/data.csv
        - echo "user3,28,manager" >> /tmp/output/data.csv
        - ls -la /tmp/output/
    outputs:
      artifacts:
      - name: raw-data
        path: /tmp/output
        archive:
          none: {}

  # --- Processeur de données ---
  - name: data-processor
    inputs:
      artifacts:
      - name: input-data
        path: /tmp/input
    container:
      image: alpine:3.20
      command: [sh, -c]
      args: |
        - echo "🧹 Processing input data..."
        - ls -la /tmp/input/
        - cat /tmp/input/data.csv
        - mkdir -p /tmp/output
        - echo "name,age,role,status" > /tmp/output/processed.csv
        - sed 's/$/,active/' /tmp/input/data.csv >> /tmp/output/processed.csv
        - echo "✅ Data processed successfully"
    outputs:
      artifacts:
      - name: clean-data
        path: /tmp/output
        archive:
          none: {}

  # --- Analyseur de résultats ---
  - name: data-analyzer
    inputs:
      artifacts:
      - name: processed-data
        path: /tmp/analysis
    container:
      image: alpine:3.20
      command: [sh, -c]
      args: |
        - echo "📊 Analyzing processed data..."
        - echo "Input files:"
        - ls -la /tmp/analysis/
        - echo "Content analysis:"
        - wc -l /tmp/analysis/processed.csv
        - echo "✅ Analysis complete!"
{{< /highlight >}}

## 🗂️ Types de stockage d'artefacts

Argo Workflows supporte plusieurs backends pour stocker vos artefacts :

| **Backend** | **Description** | **Cas d'usage** |
|-------------|-----------------|-----------------|
| **S3** | Amazon S3 ou compatible | Production, données volumineuses |
| **GCS** | Google Cloud Storage | Environnements GCP |
| **Azure** | Azure Blob Storage | Environnements Azure |
| **Git** | Dépôt Git | Configuration, scripts |
| **HTTP** | Serveur HTTP/HTTPS | APIs externes |

### Configuration S3 (exemple)

{{< highlight yaml >}}
# Configuration globale dans le ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: workflow-controller-configmap
  namespace: argo-workflows
data:
  config: |
    artifactRepository:
      s3:
        bucket: my-argo-artifacts
        endpoint: s3.amazonaws.com
        accessKeySecret:
          name: argo-artifacts
          key: accesskey
        secretKeySecret:
          name: argo-artifacts
          key: secretkey
{{< /highlight >}}

## 💡 Bonnes pratiques

### 1. Optimiser la taille des artefacts
```yaml
outputs:
  artifacts:
  - name: logs
    path: /tmp/logs
    archive:
      tar:
        compressionLevel: 9  # Compression maximale
```

### 2. Artefacts conditionnels
```yaml
outputs:
  artifacts:
  - name: error-logs
    path: /tmp/errors
    optional: true  # N'échoue pas si le fichier n'existe pas
```

### 3. Nettoyage automatique
```yaml
metadata:
  labels:
    workflows.argoproj.io/archive-strategy: "false"
spec:
  ttlStrategy:
    secondsAfterCompletion: 3600  # Supprime après 1h
```

---

# 🌐 Interface graphique

Argo Workflows possède une **UI très intuitive** pour visualiser et suivre vos workflows.

1. **Accéder à l'interface graphique :**
```bash
kubectl -n argo-workflows port-forward svc/argo-server 2746:2746
```

2. **Ouvrir dans votre navigateur :**
[http://localhost:2746](http://localhost:2746)

Vous pourrez y voir :
- L'historique des workflows
- Les logs de chaque étape
- La visualisation graphique des dépendances

---

# 🔗 Cas d’usages avancés

Argo Workflows est extrêmement flexible.
Quelques idées pour aller plus loin :

- **CI/CD GitOps**
  Déployer vos applications avec Argo Workflows en complément d'ArgoCD.

- **Machine Learning (MLOps)**
  Orchestrer des pipelines de training et de déploiement de modèles.

- **Traitement de données**
  Lancer des jobs Spark ou ETL directement dans Kubernetes.

- **Automatisation d'infra**
  Générer et appliquer des manifests Kubernetes via Terraform/Helm.

---

# ✅ Conclusion

Argo Workflows est un outil puissant pour orchestrer vos pipelines dans Kubernetes :
- Définition **déclarative** et versionnable
- Exécution **scalable** grâce aux Pods
- Intégration parfaite avec le reste de l'écosystème Argo

Prochaine étape ?
- Lier Argo Workflows avec **Argo Events** pour du véritable **event-driven orchestration**
