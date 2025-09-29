---
title: "⚡ Argo Workflows : Transforme tes jobs Kubernetes en pipelines !"
date: 2025-09-29
summary: "Fini les scripts bash dispersés ! Avec Argo Workflows, orchestrez des pipelines complexes directement dans Kubernetes."
tags: ["Kubernetes", "GitOps", "DevOps", "Argo", "Workflows"]
categories: ["Automation"]
featuredImage: "featured.png"
---

# 💥 STOP aux scripts bash ingérables

## 😤 Le cauchemar quotidien du DevOps

**8h du matin** : "Je lance mon script de déploiement..."

```bash
#!/bin/bash
./build.sh && ./test.sh && ./push.sh && ./notify-slack.sh
# 🤞 Espérons que tout se passe bien...
```

**8h05** : Le script plante à l'étape 3 sur 47 💀
**8h30** : Tu réalises que tu dois tout relancer depuis le début.
**9h00** : Café froid, morale en berne ☕

## 🎯 Argo Workflows : L'orchestrateur Kubernetes

Avec **Argo Workflows**, vous pouvez :
- ✅ **Visualiser** vos pipelines en temps réel
- ✅ **Relancer** uniquement l'étape qui a échoué
- ✅ **Exécuter en parallèle** pour gagner du temps
- ✅ **Monitorer** chaque étape individuellement
- ✅ **Gérer les ressources dynamiquement**
- ✅ **Déboguer** facilement grâce à des logs clairs

Tout est **déclaratif** (YAML), versionné dans Git et s'exécute **nativement sur Kubernetes**. 🚀

---

# 🧠 Architecture d'Argo Workflows

## Les composants clés

```
📜 WorkflowTemplate  →  🎬 Workflow  →  🏃‍♂️ Pods  →  ✅ Résultats
```

| **Composant** | **Rôle** | **Exemple** |
|---------------|----------|-------------|
| 🎯 **Workflow** | Pipeline en cours d'exécution | CI/CD en action |
| 📋 **WorkflowTemplate** | Modèle réutilisable | "Build & Deploy" |
| ⏰ **CronWorkflow** | Planification automatique | Backup chaque nuit |
| 👑 **WorkflowController** | Orchestrateur global | Gère et supervise |

## Types de workflows

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

# 🛠️ Installation rapide

## 1. Déploiement du contrôleur et de l'UI

```bash
kubectl create namespace argo-workflows
kubectl apply -n argo-workflows -f https://raw.githubusercontent.com/argoproj/argo-workflows/stable/manifests/quick-start-minimal.yaml
kubectl get pods -n argo-workflows
```

Vous devriez voir :
```
workflow-controller-xxx   Running
argo-server-xxx           Running
```

## 2. Installer la CLI Argo

```bash
# Linux
curl -sLO https://github.com/argoproj/argo-workflows/releases/latest/download/argo-linux-amd64.gz
gunzip argo-linux-amd64.gz
chmod +x argo-linux-amd64
sudo mv argo-linux-amd64 /usr/local/bin/argo

# macOS
brew install argo
```

Vérification :
```bash
argo version
```

---

# 🎬 Démonstration : pipeline de données

## Objectif

Créer un pipeline qui :
1. 📥 Récupère des données
2. 🧹 Les nettoie et génère des métadonnées **en parallèle**
3. 🔗 Agrège le tout
4. 🚀 Déploie le résultat en production

## WorkflowTemplate

```yaml
apiVersion: argoproj.io/v1alpha1
kind: WorkflowTemplate
metadata:
  name: data-pipeline
  namespace: argo-workflows
spec:
  entrypoint: main
  templates:
  - name: main
    dag:
      tasks:
      - name: fetch
        template: fetch-data
      - name: clean
        dependencies: [fetch]
        template: clean-data
      - name: generate-metadata
        dependencies: [fetch]
        template: metadata-generator
      - name: aggregate
        dependencies: [clean, generate-metadata]
        template: aggregator
      - name: deploy
        dependencies: [aggregate]
        template: production-deploy

  - name: fetch-data
    container:
      image: curlimages/curl:8.4.0
      command: ["sh", "-c"]
      args: ["echo 'Fetching data...' && sleep 2"]

  - name: clean-data
    container:
      image: alpine:3.20
      command: ["sh", "-c"]
      args: ["echo 'Cleaning data...' && sleep 1"]

  - name: metadata-generator
    container:
      image: alpine:3.20
      command: ["sh", "-c"]
      args: ["echo 'Generating metadata...' && sleep 1"]

  - name: aggregator
    container:
      image: alpine:3.20
      command: ["sh", "-c"]
      args: ["echo 'Aggregating results...' && sleep 1"]

  - name: production-deploy
    container:
      image: alpine:3.20
      command: ["sh", "-c"]
      args: ["echo 'Deploying to production 🚀'"]
```

---

# 🚦 Fonctionnalités clés

## Retry automatique
```yaml
retryStrategy:
  limit: 3
  backoff:
    duration: "30s"
    factor: 2
```

## Conditions intelligentes + parameters

Il est possible de passer des parameters de step en step, et il est possible de faire des conditions de lancement de step :

```yaml
- name: deploy-prod
  when: "{{workflow.parameters.env}} == 'production'"
  template: production-step
```

## Artifacts avec S3

Les Artifacts sont un concept clés dans Argo Workflow c'est ce qui va vous donner la possibilité de transmettre a l'étape d'aprés un fichier/dossier ou bien de le déposer dans un registry a la fin

```yaml
outputs:
  artifacts:
  - name: report
    path: /tmp/output
    s3:
      bucket: my-artifacts
      key: "{{workflow.name}}/report.tar.gz"
```

---

# ⏰ CronWorkflows : automatisation planifiée

```yaml
apiVersion: argoproj.io/v1alpha1
kind: CronWorkflow
metadata:
  name: nightly-backup
  namespace: argo-workflows
spec:
  schedule: "0 2 * * *"  # Tous les jours à 2h
  workflowSpec:
    entrypoint: backup
    templates:
    - name: backup
      container:
        image: postgres:15
        command: ["sh", "-c"]
        args: ["pg_dump $DB_URL > /tmp/backup.sql"]
        env:
        - name: DB_URL
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: url
```

---

# 🖥️ Interface graphique

```bash
kubectl -n argo-workflows port-forward svc/argo-server 2746:2746
```

Ouvrez [http://localhost:2746](http://localhost:2746) pour :
- 📊 **Visualiser vos workflows**
- 🔍 **Consulter les logs**
- 🔄 **Relancer ou annuler des workflows**
- 🗂️ **Explorer les artifacts**

---

# 🏆 Bonnes pratiques

1. **Utiliser des WorkflowTemplates** pour la réutilisabilité.
2. **Séparer vos workflows par namespace** pour l'isolation.
3. **Définir des Resource Requests/Limits** pour chaque étape.
4. **Sécuriser avec des ServiceAccounts dédiés**.
5. **Surveiller via Prometheus/Grafana** pour détecter les anomalies.

---

# 🔗 Ressources utiles

- [Documentation Argo Workflows](https://argoproj.github.io/argo-workflows/)
- [Exemples officiels](https://github.com/argoproj/argo-workflows/tree/master/examples)
- [Argo Community Slack](https://argoproj.github.io/community/join-slack)

---

Avec Argo Workflows, transformez vos scripts éparpillés en pipelines robustes, scalables et traçables directement dans Kubernetes. 🚀
