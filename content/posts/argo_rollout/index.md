---
title: "Argo Rollouts + Istio : déploiements progressifs et routage fin pour des mises à jour sûres"
date: 2025-09-19
summary: "Utiliser Argo Rollouts avec Istio pour faire des canary/weighted/traffic-splitting vers des sous-populations, et bonnes pratiques DB pour supporter deux versions"
tags: ["Kubernetes", "GitOps", "DevOps", "Argo", "Istio", "Deployment"]
categories: ["Deployment", "Canary"]
featuredImage: "featured.png"
---

# Introduction

Les mises en production progressives (canary, blue-green, progressive delivery) sont aujourd'hui indispensables pour réduire le risque lors des releases. **Argo Rollouts** apporte des stratégies de déploiement avancées (canary, blue-green, experiments) et s'intègre nativement avec des meshes comme **Istio** pour piloter finement le trafic vers une **sous-population** ciblée (par header, cookie, subset, or percentage).

Cet article explique :
- Comment installer et configurer **Argo Rollouts** et **Istio**.
- Comment configurer un **Canary** avec routage Istio vers une partie précise de la population.
- Les implications au niveau base de données : comment rendre le code DB compatible avec les deux versions simultanées (backward / forward compatibility).

---

# 🧩 Concepts clés

- **Argo Rollouts** : contrôleur Kubernetes qui remplace/complète le Deployment pour piloter des stratégies de déploiement progressives et observables.
- **Istio** : service mesh qui gère le routage, la résilience, la sécurité et la télémétrie entre services. Il expose des ressources CRD comme `VirtualService` et `DestinationRule` pour contrôler le trafic.
- **TrafficRouting (Argo ↔ Istio)** : Argo Rollouts manipule les objets Istio (VirtualService / DestinationRule) pour faire varier les poids ou diriger une fraction de la population vers la révision "canary".
- **DB compatibility** : pendant un canary, deux versions de l'application coexistent. Il faut s'assurer que la **base de données** comprend les deux schémas / comportements ou que les migrations sont **expand-contract** pour être compatibles avec les deux versions.

---

# ⚙️ Installation rapide

## 1) Installer Istio (minimal)
> Choisir une install adaptée à ton cluster (istioctl, operator, helm). Exemple minimal :
```bash
istioctl install --set profile=minimal -y
kubectl label namespace default istio-injection=enabled
```

## 2) Installer Argo Rollouts
```bash
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://raw.githubusercontent.com/argoproj/argo-rollouts/stable/manifests/install.yaml
kubectl -n argo-rollouts get deploy
```

Installer l'outil `kubectl-argo-rollouts` (utile pour observer et manipuler les rollouts) :
```bash
# macOS (Homebrew)
brew install argoproj/tap/kubectl-argo-rollouts

# ou depuis curl
curl -sLO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-darwin-amd64
chmod +x kubectl-argo-rollouts-darwin-amd64 && mv kubectl-argo-rollouts-darwin-amd64 /usr/local/bin/kubectl-argo-rollouts
```

Vérifier l'installation :
```bash
kubectl argo rollouts get all -n <your-namespace>
```

---

# 🎬 Exemple : Canary ciblé avec Istio (subset + header)

Objectif : mettre à jour un service `web` et envoyer les 10% du trafic vers la nouvelle version **ET** diriger les utilisateurs avec header `X-Canary: true` vers la nouvelle version (targeted users).

Architecture minimale :
- `Service web` exposé via Istio Gateway / VirtualService.
- `DestinationRule` avec deux subsets : `stable` et `canary`.
- `Rollout` Argo qui crée une nouvelle ReplicaSet et demande à Istio de modifier les poids.

## 1) Déployer le Service initial (Deployment remplacé par Rollout)

```yaml
# rollout-web.yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: web
  namespace: demo
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: web
          image: docker.io/yourorg/web:stable # version initiale
          ports:
            - containerPort: 8080
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
  strategy:
    canary:
      trafficRouting:
        istio:
          virtualService:
            name: web-vs
            routes:
              - web
      steps:
        - setWeight: 10       # 10% du trafic vers canary au step 1
        - pause: {duration: 10s}
        - setWeight: 50       # 50% au step 2
        - pause: {duration: 10s}
        - setWeight: 100
```

> Le champ `trafficRouting.istio.virtualService` indique à Argo Rollouts quel VirtualService modifier (et quelle route) pour ajuster le split du trafic.

## 2) DestinationRule

```yaml
# destinationrule-web.yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: web-destination
  namespace: demo
spec:
  host: web.demo.svc.cluster.local
  subsets:
    - name: stable
      labels:
        version: stable
    - name: canary
      labels:
        version: canary
```

## 3) VirtualService (routage selon header + weight)

```yaml
# virtualservice-web.yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: web-vs
  namespace: demo
spec:
  hosts:
    - "web.demo.svc.cluster.local"
  http:
    - name: web
      match:
        - headers:
            x-canary:
              exact: "true"
      route:
        - destination:
            host: web.demo.svc.cluster.local
            subset: canary
          weight: 100
    - name: web-default
      route:
        - destination:
            host: web.demo.svc.cluster.local
            subset: stable
          weight: 100
```

> Ici on définit d'abord une règle prioritaire : si le header `X-Canary: true` est présent, on route directement vers `canary`. Le VirtualService principal sera manipulé par Argo Rollouts pour ajuster les poids sur la `route` nommée `web` (cf `routes: - web` dans le Rollout).

## 4) Assurer que les pods portent le label subset approprié

Argo Rollouts gère automatiquement l'étiquetage `version: canary` pour le ReplicaSet canary si tu configures `podTemplate` correctement (les subsets doivent correspondre aux labels du Pod). Exemple : le template stable contient `version: stable` ; quand Argo Rollouts crée la nouvelle révision il faut que le Pod template ait `version: canary` (ou utilise `rollout.kubernetes.io` annotations si nécessaire).

Important : adapte tes labels dans `template.metadata.labels` pour correspondre aux subsets du DestinationRule.

---

# ✅ Workflow de déploiement (commande & observation)

1. Appliquer les manifestes :
```bash
kubectl apply -f destinationrule-web.yaml -n demo
kubectl apply -f virtualservice-web.yaml -n demo
kubectl apply -f rollout-web.yaml -n demo
```

2. Lancer une mise à jour d'image (changer `image: ...:canary`) et appliquer :
```bash
# modifier rollout-web.yaml : image: docker.io/yourorg/web:canary
kubectl apply -f rollout-web.yaml -n demo
```

3. Suivre le rollout :
```bash
kubectl argo rollouts get rollout web -n demo --watch
kubectl argo rollouts promote web -n demo        # forcer la promotion (si configured)
kubectl argo rollouts pause web -n demo          # pause
kubectl argo rollouts resume web -n demo         # resume
kubectl argo rollouts abort web -n demo          # rollback
```

Argo Rollouts modifiera automatiquement le `VirtualService` pour appliquer les `setWeight` définis dans ta stratégie si la configuration `trafficRouting.istio` est correcte.

---

# ⚠️ Points critiques & bonnes pratiques (DB, compatibilité et tests)

Lorsque tu fais un canary **avec deux versions coexistant**, la base de données est souvent le point de friction. Voici les principes et patterns à suivre.

## 1) Principes généraux de compatibilité DB

- **Expand-Contract (Backward/Forward compatible migrations)** :
  - Étape *Expand* : ajouter des colonnes, tables, ou flags nécessaires pour la nouvelle version, mais ne pas enlever ni changer le comportement de l'ancienne version.
  - Déployer la nouvelle application (les deux versions lisent/écrivent le nouveau champ si nécessaire).
  - Étape *Contract* : lorsque l'ancienne version a disparu (promotion complète), enlever les codes/colonnes obsolètes.

- **Pas de breaking changes** immédiats :
  - Éviter de renommer, supprimer ou changer le type d'une colonne sans migration progressive.
  - Si un comportement transactionnel change, s'assurer que l'ancien code reste supporté.

- **Feature flags / toggles** :
  - Utiliser des flags pour activer progressivement les nouvelles fonctionnalité côté application sans forcer immédiatement tous les utilisateurs à migrer.

- **Dual-read / Dual-write** (avec prudence) :
  - En période de migration, la nouvelle version peut écrire dans le nouveau champ tout en maintenant l'ancien pour compatibilité, ou effectuer un write to both pattern si nécessaire (attention à l'idempotence).

- **Adapter layer / compatibility layer** :
  - Isoler la logique DB (repository/DAO) derrière une couche qui peut router la lecture/écriture selon version ou flag.

## 2) Tests & validité pendant le canary

- **Tests d'intégration** entre la version canary et la base de données (incluant rollback tests).
- **Canary DB queries** : vérifier que la charge du canary n'introduit pas de requêtes coûteuses non-indexées.
- **Monitoring** : métriques DB (latency, errors), et alertes (p99, qps, error rate) pendant chaque étape du canary.
- **Backups / Point-in-time recovery** : toujours possible d'annuler des migrations si nécessaire.

## 3) Exemple de flow de migration simple

1. *Expand* : ajouter colonne `new_col` NULLABLE.
2. Déployer app v2 qui écrit `new_col` mais lit d'abord l'ancien champ si `new_col` absent.
3. Monitorer canary (erreurs & latences).
4. Une fois stable, backfill `new_col` pour les anciennes lignes (optionnel).
5. Déployer app v3 : lire `new_col` exclusivement.
6. *Contract* : supprimer l'ancien champ si plus utilisé.

---

# 🔍 Observabilité & SLI pendant canary

- Exposer métriques essentielles : erreur 5xx, latence p50/p95/p99, saturation CPU/RAM, DB erreurs.
- Utiliser Istio + Prometheus + Grafana pour mesurer la performance segmentée (par subset ou par header).
- Argo Rollouts peut intégrer des **Analysis** templates (Prometheus) pour automatiser les checks entre steps :
  - Si un metric dépasse le seuil, le rollout se rollback automatiquement.

Exemple d'analysis (sous forme simplifiée) :
```yaml
analysis:
  templates:
  - name: success-rate-check
    metric:
      name: request_success_rate
      provider:
        prometheus:
          address: http://prometheus.monitoring.svc:9090
      successCondition: result > 0.99
      failureCondition: result < 0.95
```

---

# ✅ Conclusion & recommandations rapides

- **Argo Rollouts + Istio** : combo puissant pour piloter qui reçoit le trafic (pourcentage ou segment ciblé via header/subset).
- **Targeted rollouts** : utiliser header-based routing pour tester des utilisateurs réels (beta users), ou subset-based + weight pour tests A/B.
- **DB compatibility** : ne sous-estime jamais la complexité — applique les patterns *expand-contract*, feature flags, tests d'intégration, et observabilité.
- **Automatisation** : combine Argo Rollouts analysis + Prometheus pour rollbacks automatiques en cas de régression.

---

# Annexes : resources utiles

- Argo Rollouts docs : https://argoproj.github.io/argo-rollouts/
- Istio docs : https://istio.io/
- Patterns DB : expand-contract migrations, feature flags, dual-write patterns (recherche "expand and contract database migrations", "backwards compatible database changes")
