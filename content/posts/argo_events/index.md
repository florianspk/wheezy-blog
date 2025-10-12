---
title: "Argo Events 🎯 - Automatisez vos réactions dans Kubernetes"
date: 2025-10-12
summary: "Fini les CRON jobs approximatifs ! Avec Argo Events, Kubernetes devient un orchestrateur réactif et fiable."
tags: ["Kubernetes", "GitOps", "DevOps", "Argo", "Events"]
categories: ["Automation"]
featuredImage: "featured.png"
---

# 🚨 Dites adieu aux CRON jobs peu fiables

## Pourquoi changer d'approche

Dans beaucoup d'environnements, on retrouve encore :
- 📅 Des **CRON jobs** qui se déclenchent en retard… ou pas du tout
- 🐌 Des scripts qui vérifient en boucle si un événement est arrivé
- 🤷 Des webhooks bricolés et instables
- 😩 Des pipelines qui démarrent avec plusieurs minutes de décalage

**Problème :** votre infrastructure reste lente et fragile.

**Solution :** grâce à **Argo Events**, Kubernetes peut réagir **immédiatement** à tout type d'événement.

Exemples concrets :
- Commit GitHub → Déploiement automatique
- Fichier ajouté dans S3 → Job de traitement instantané
- Alerte Prometheus → Remédiation automatisée
- Message Slack → Déclenchement d'un workflow de validation

---

# 🧠 Architecture d'Argo Events

Argo Events repose sur trois composants clés :

```
📡 EventSource → 🧠 Sensor → 🚀 Trigger
```

| Composant        | Rôle | Exemple |
|------------------|------|---------|
| **EventSource**  | Écoute les événements externes | GitHub, S3, Kafka, Redis |
| **Sensor**       | Analyse et décide selon des règles | "Si branche = main → Déploiement" |
| **Trigger**      | Déclenche une action | Workflow, Job, notification Slack |

---

# ⚡ Installation rapide

## Étapes principales

```bash
# Namespace dédié
kubectl create namespace argo-events

# Installation des composants Argo Events
kubectl apply -n argo-events -f https://raw.githubusercontent.com/argoproj/argo-events/stable/manifests/install.yaml

# Vérification
kubectl get pods -n argo-events
```

Pods attendus :
```
eventbus-default-stan-0                 Running
eventsource-controller-xxx              Running
sensor-controller-xxx                   Running
workflow-controller-xxx                 Running
```

---

# 🎬 Démonstration : d'un webhook à un Workflow

Objectif : Déclencher un workflow Kubernetes à partir d'une requête HTTP.

## Étape 1 : Créer un WorkflowTemplate

```yaml
apiVersion: argoproj.io/v1alpha1
kind: WorkflowTemplate
metadata:
  name: hello-world-magic
  namespace: argo-events
spec:
  entrypoint: say-hello
  templates:
  - name: say-hello
    inputs:
      parameters:
      - name: message
        value: "Hello from Argo Events"
    container:
      image: alpine:3.20
      command: [sh, -c]
      args: ["echo '{{inputs.parameters.message}}'"]
```

---

## Étape 2 : Créer un EventSource

```yaml
apiVersion: argoproj.io/v1alpha1
kind: EventSource
metadata:
  name: webhook-magic
  namespace: argo-events
spec:
  service:
    ports:
      - port: 12000
        targetPort: 12000
  webhook:
    hello-trigger:
      endpoint: /webhook/hello
      method: POST
      port: "12000"
```

---

## Étape 3 : Créer un Sensor

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Sensor
metadata:
  name: webhook-sensor
  namespace: argo-events
spec:
  dependencies:
    - name: hello-webhook-dep
      eventSourceName: webhook-magic
      eventName: hello-trigger
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
                generateName: hello-event-triggered-
                namespace: argo-events
              spec:
                workflowTemplateRef:
                  name: hello-world-magic
                arguments:
                  parameters:
                  - name: message
                    value: "{{.Input.body.message}}"
```

---

# 🚀 Test de bout en bout

Exposez votre webhook :
```bash
kubectl port-forward svc/webhook-magic-eventsource-svc 12000:12000 -n argo-events
```

Déclenchez-le avec `curl` :
```bash
curl -X POST http://localhost:12000/webhook/hello   -H "Content-Type: application/json"   -d '{
    "message": "Mon premier workflow automatique !"
  }'
```

Vérifiez l'exécution :
```bash
kubectl get wf -n argo-events
kubectl logs -n argo-events -l workflows.argoproj.io/workflow=<workflow-name>
```

---

# 🔧 Aller plus loin

- **Sources d'événements avancées :**
  - GitHub pour la CI/CD
  - S3 ou MinIO pour la data
  - Prometheus pour la supervision
  - Calendrier pour des tâches planifiées

- **Actions déclenchées :**
  - Workflows complexes avec Argo Workflows
  - Synchronisation GitOps avec ArgoCD
  - Notifications Slack ou autres systèmes externes

---

# 📈 Bénéfices d'Argo Events

- ⚡ Réactivité en millisecondes
- 🎯 Déclenchements précis et conditionnels
- 🛡️ Système robuste et Kubernetes-native
- 📈 Scalabilité pour traiter des milliers d'événements
- 🔧 Flexibilité pour connecter n'importe quel système

---

# 📚 Ressources

- [Documentation officielle Argo Events](https://argoproj.github.io/argo-events/)
- [Exemples GitHub](https://github.com/argoproj/argo-events/tree/master/examples)
