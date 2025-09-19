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
