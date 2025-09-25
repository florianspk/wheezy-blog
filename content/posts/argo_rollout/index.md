---
title: "🚀 Argo Rollouts + NGINX : Déployez sans stress avec des canary qui claquent !"
date: 2025-10-27
summary: "Fini les déploiements qui font flipper ! Avec Argo Rollouts et NGINX, vos canary deployments deviennent simples, fiables et progressifs 🎯"
tags: ["Kubernetes", "GitOps", "DevOps", "Argo", "NGINX", "Deployment"]
categories: ["Deployment", "Canary"]
featuredImage: "featured.png"
---

# 💥 Arrête de stresser à chaque déploiement !

Tu connais cette sensation ? **10h, déploiement en prod, mains moites, café froid** ☕

Tu te dis : "Allez, cette fois ça va le faire... 🤞"

**BOOM ! 💥** Service avec de nouveau bug, les utilisateurs qui râlent, ton boss qui t'envoie des messages passive-agressifs sur Slack. Tu te dépêches à essayer de rollback ou bien de créer une nouvelle version ...

## 🎭 Le drame des déploiements classiques

Avec un déploiement Kubernetes classique, c'est **tout ou rien** :
- ✅ Ça marche → Tu es un héros ! 🦸‍♂️
- ❌ Ça plante → Tu es grillé... 🔥

Mais imagine si tu pouvais tester ta nouvelle version sur **seulement 5% des utilisateurs** avant de la déployer à tous ?

C'est exactement ce que fait **Argo Rollouts** ! 🎯

---

# 🧠 Les concepts clés

## 🎨 Les composants principaux

- **Argo Rollouts** : le contrôleur qui remplace le `Deployment` classique pour gérer des déploiements progressifs intelligents.
- **NGINX Ingress Controller** : le répartiteur de trafic qui décide quelle version reçoit quel pourcentage de requêtes.
- **Canary Service & Stable Service** : deux services Kubernetes distincts, l'un pour la version **canary**, l'autre pour la version **stable**.
- **Traffic Splitting** : la capacité à router progressivement le trafic entre les deux versions (ex. 10% / 90%).

## 🎪 Le spectacle du canary deployment

Au lieu de déployer directement votre nouvelle version à 100% des utilisateurs, vous la faites monter progressivement :
1. **5%** des utilisateurs → validation initiale
2. **20%** des utilisateurs → montée progressive
3. **50%** des utilisateurs → confiance grandissante
4. **100%** des utilisateurs → bascule complète 🚀

À **chaque étape**, en cas de problème, vous pouvez revenir immédiatement en arrière.

---

# 🛠️ Installation rapide

## 1️⃣ Déployer NGINX Ingress Controller

```bash
# Méthode recommandée via Helm
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx

# Méthode manuelle via manifest officiel
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
```

## 2️⃣ Installer Argo Rollouts

```bash
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://raw.githubusercontent.com/argoproj/argo-rollouts/stable/manifests/install.yaml

kubectl -n argo-rollouts get deploy
```

## 3️⃣ Installer la CLI Argo Rollouts

```bash
# macOS
brew install argoproj/tap/kubectl-argo-rollouts

# Linux
curl -sLO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
chmod +x kubectl-argo-rollouts-linux-amd64
mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts
```

Vérification :
```bash
kubectl argo rollouts version
```

---

# 🎬 Démonstration : déploiement canary progressif

Objectif : déployer une application qui passe d'une version **bleue** à une version **jaune** avec une montée progressive de 5% → 100%.

## Étape 1 : Déployer les services nécessaires

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: rollouts-demo
---
apiVersion: v1
kind: Service
metadata:
  name: rollouts-demo
  namespace: rollouts-demo
spec:
  ports:
    - port: 80
      targetPort: http
      protocol: TCP
      name: http
  selector:
    app: rollouts-demo
---
apiVersion: v1
kind: Service
metadata:
  name: rollouts-demo-canary
  namespace: rollouts-demo
spec:
  ports:
    - port: 80
      targetPort: http
      protocol: TCP
      name: http
  selector:
    app: rollouts-demo
---
apiVersion: v1
kind: Service
metadata:
  name: rollouts-demo-stable
  namespace: rollouts-demo
spec:
  ports:
    - port: 80
      targetPort: http
      protocol: TCP
      name: http
  selector:
    app: rollouts-demo
```

## Étape 2 : Créer le Rollout

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: rollouts-demo
  namespace: rollouts-demo
spec:
  replicas: 5
  strategy:
    canary:
      canaryService: rollouts-demo-canary
      stableService: rollouts-demo-stable
      trafficRouting:
        nginx:
          stableIngress: rollouts-demo
      steps:
        - setWeight: 5
        - pause: {}
        - setWeight: 20
        - pause: { duration: 10 }
        - setWeight: 40
        - pause: { duration: 10 }
        - setWeight: 60
        - pause: { duration: 10 }
        - setWeight: 80
        - pause: { duration: 10 }
  selector:
    matchLabels:
      app: rollouts-demo
  template:
    metadata:
      labels:
        app: rollouts-demo
    spec:
      containers:
        - name: rollouts-demo
          image: argoproj/rollouts-demo:blue
          ports:
            - name: http
              containerPort: 8080
              protocol: TCP
```

## Étape 3 : Créer l'Ingress pour router le trafic

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rollouts-demo
  namespace: rollouts-demo
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  ingressClassName: nginx
  rules:
    - host: argo-rollout.localhost
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: rollouts-demo-stable
                port:
                  number: 80
```

---

# 🚀 Lancer et superviser le canary

## Déploiement initial
```bash
kubectl apply -f demo-setup.yaml
kubectl apply -f rollout-demo.yaml
kubectl apply -f ingress-demo.yaml
```

Vérifiez :
```bash
kubectl argo rollouts get rollout rollouts-demo -n rollouts-demo
kubectl get pods -n rollouts-demo
```

## Déploiement de la nouvelle version
```bash
kubectl argo rollouts set image rollouts-demo rollouts-demo=argoproj/rollouts-demo:yellow -n rollouts-demo
kubectl argo rollouts get rollout rollouts-demo -n rollouts-demo --watch
```

Promotion ou rollback :
```bash
kubectl argo rollouts promote rollouts-demo -n rollouts-demo
kubectl argo rollouts abort rollouts-demo -n rollouts-demo
```

---

# 📊 Supervision et automatisation

Ajoutez un **AnalysisTemplate** pour surveiller les métriques et automatiser les décisions :

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: success-rate-guardian
  namespace: rollouts-demo
spec:
  metrics:
  - name: success-rate
    provider:
      prometheus:
        address: http://prometheus.monitoring.svc:9090
        query: |
          sum(rate(http_requests_total{job="rollouts-demo",code!~"5.."}[5m])) /
          sum(rate(http_requests_total{job="rollouts-demo"}[5m])) * 100
    successCondition: result[0] >= 95
    failureCondition: result[0] < 90
```

---

# 🏆 Récapitulatif

Avec **Argo Rollouts** et **NGINX**, vous obtenez :
- Déploiements progressifs et sécurisés
- Rollback instantané en cas d'échec
- Visibilité et contrôle total
- Automatisation grâce à l'intégration avec des métriques

---

# 🔗 Ressources

- [Documentation Argo Rollouts](https://argoproj.github.io/argo-rollouts/)
- [Traffic management avec NGINX](https://argoproj.github.io/argo-rollouts/features/traffic-management/nginx/)
