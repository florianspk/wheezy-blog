---
title: "Argo Events : automatiser vos workflows Kubernetes en mode event-driven"
date: 2025-09-19
summary: "Déclencher automatiquement vos Workflows Argo grâce à un moteur d'événements Kubernetes-native"
tags: ["Kubernetes", "GitOps", "DevOps", "Argo"]
categories: ["Automation"]
featuredImage: "featured.png"
---

# Introduction

## 🚀 Pourquoi Argo Events ?

Dans le monde du **DevOps moderne**, les infrastructures évoluent vers des systèmes **event-driven**.
Tout devient un événement : un commit sur GitHub, une image Docker poussée sur un registry, un fichier déposé dans S3, ou encore une alerte Prometheus.

Traditionnellement, on déclenche des pipelines via des **CRON jobs** ou des **webhooks** intégrés dans la CI/CD.
Le problème ?
- ❌ Peu de traçabilité
- ❌ Complexité à orchestrer plusieurs événements
- ❌ Pas de gestion déclarative dans Kubernetes

C'est là qu'entre en scène **Argo Events**, le **moteur d'événements Kubernetes-native** de la suite Argo.

Avec Argo Events, vous pouvez :

- Définir **déclarativement** vos sources d'événements (`EventSource`)
- Définir **comment réagir** à ces événements via des `Sensor`
- Déclencher des **actions** (`Trigger`), comme :
  - Un **Workflow Argo**
  - Un **Job Kubernetes**
  - Une **notification Slack**
  - Un **pipeline GitOps** via ArgoCD

---

## 🧩 Architecture d'Argo Events

Argo Events repose sur trois composants principaux :

| **Composant**   | **Rôle** |
|-----------------|----------|
| **EventSource** | Définit **d'où vient l'événement** (Webhook, Kafka, S3, GitHub, etc.) |
| **Sensor** | Écoute un ou plusieurs EventSources et définit la logique de traitement |
| **Trigger** | L'action déclenchée quand l'événement est reçu (ex: workflow, job, notification) |

Schéma simplifié :

```
[Webhook GitHub] → EventSource → Sensor → Trigger (Workflow)
```

💡 **Avantage clé** : chaque élément est un **CRD Kubernetes**, donc versionnable dans Git → idéal pour une approche **GitOps**.

---

# ⚙️ Mise en place d'Argo Events

## 📥 Installation

> **Pré-requis** : un cluster Kubernetes fonctionnel (kind, k3d, Talos, etc.), `kubectl` et `helm`.

1. **Créer un namespace dédié**
```bash
kubectl create namespace argo-events
```

2. **Installer les composants Argo Events**
```bash
kubectl apply -n argo-events -f https://raw.githubusercontent.com/argoproj/argo-events/stable/manifests/install.yaml
```

3. **Vérifier que tout est OK**
```bash
kubectl get pods -n argo-events
```

Vous devriez voir quelque chose comme :
```
eventbus-default-stan-0     Running
eventsource-controller       Running
sensor-controller            Running
workflow-controller          Running
```

---

# 🎬 Exemple live : déclencher un Workflow via un Webhook

Objectif de la démo :
- Déclencher automatiquement un **Workflow Argo** via un simple `curl POST`.
- Le workflow exécutera une tâche simple (container `whalesay`).

---

## 1️⃣ Définir un WorkflowTemplate

On commence par définir un **template réutilisable** de workflow.

```yaml
# hello-workflow.yaml
apiVersion: argoproj.io/v1alpha1
kind: WorkflowTemplate
metadata:
  name: hello-argo-events
  namespace: argo-events
spec:
  entrypoint: whalesay
  templates:
  - name: whalesay
    container:
      image: docker/whalesay:latest
      command: [cowsay]
      args: ["Hello from Argo Events!"]
```

Appliquer le fichier :
```bash
kubectl apply -f hello-workflow.yaml
```

---

## 2️⃣ Créer l'EventSource (Webhook)

L'**EventSource** sera une simple API REST qui écoute les requêtes entrantes.

```yaml
# webhook-eventsource.yaml
apiVersion: argoproj.io/v1alpha1
kind: EventSource
metadata:
  name: webhook
  namespace: argo-events
spec:
  service:
    ports:
      - port: 12000
        targetPort: 12000
  webhook:
    hello-webhook:
      endpoint: /hello
      method: POST
      port: "12000"
```

Appliquer le fichier :
```bash
kubectl apply -f webhook-eventsource.yaml
```

Vérifier que le pod démarre :
```bash
kubectl get pods -n argo-events
```

---

## 3️⃣ Créer le Sensor (écoute + trigger)

Le **Sensor** écoute notre `EventSource` et soumet automatiquement un workflow à chaque requête.

```yaml
# webhook-sensor.yaml
apiVersion: argoproj.io/v1alpha1
kind: Sensor
metadata:
  name: webhook-sensor
  namespace: argo-events
spec:
  dependencies:
    - name: hello-dep
      eventSourceName: webhook
      eventName: hello-webhook
  triggers:
    - template:
        name: trigger-hello-workflow
        argoWorkflow:
          operation: submit
          source:
            resource:
              apiVersion: argoproj.io/v1alpha1
              kind: Workflow
              metadata:
                generateName: hello-triggered-
                namespace: argo-events
              spec:
                workflowTemplateRef:
                  name: hello-argo-events
```

Appliquer le fichier :
```bash
kubectl apply -f webhook-sensor.yaml
```

---

## 4️⃣ Tester le tout

1. **Rediriger le port du webhook localement :**
```bash
kubectl port-forward svc/webhook-eventsource-svc 12000:12000 -n argo-events
```

2. **Envoyer un événement :**
```bash
curl -X POST http://localhost:12000/hello -d '{"message":"trigger"}'
```

3. **Vérifier le déclenchement :**
```bash
kubectl get wf -n argo-events
```

Vous devriez voir un workflow `hello-triggered-xxxx`.

4. **Afficher les logs du workflow :**
```bash
kubectl logs -n argo-events -l workflows.argoproj.io/workflow=hello-triggered-xxxx
```

Résultat attendu :
```
Hello from Argo Events!
```

🎉 **Bravo !** Votre premier workflow déclenché automatiquement via un événement est opérationnel.

---

# 🌐 Observabilité & UI

Argo Events s'intègre parfaitement avec l'UI d'Argo Workflows.

1. Installer l'interface graphique :
```bash
kubectl apply -n argo-events -f https://raw.githubusercontent.com/argoproj/argo-workflows/stable/manifests/quick-start-postgres.yaml
```

2. Accéder à l'UI :
```bash
kubectl port-forward svc/argo-server 2746:2746 -n argo-events
```

Interface disponible sur : [http://localhost:2746](http://localhost:2746)

---

# 🔗 Cas d’usage avancés

Voici quelques idées pour aller plus loin :

- **CI/CD GitOps**
  Déclencher un déploiement ArgoCD dès qu'un commit est pushé sur GitHub.

- **Data pipeline**
  Lancer un workflow ML automatiquement quand un fichier est déposé dans S3.

- **Monitoring & alerting**
  Réagir à une alerte Prometheus en déclenchant un job correctif.

- **Fan-out**
  Déclencher plusieurs workflows en parallèle depuis un seul événement.

---

# ✅ Conclusion

En combinant **Argo Events** et **Argo Workflows**, vous disposez d'une **plateforme d'orchestration event-driven Kubernetes-native** :

- 🎯 Définition déclarative des pipelines et triggers
- 🔒 Intégration GitOps native
- 🌐 Support de nombreuses sources d'événements
- 📈 Observabilité et traçabilité intégrées

Dans cette démo, nous avons déclenché un workflow via un simple webhook, mais les possibilités sont infinies.
Prochaine étape ? Intégrer Argo Events avec **Kafka**, **GitHub** ou **ArgoCD** pour automatiser entièrement vos flux DevOps.
