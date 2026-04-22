---

title: "Stockage hyperconvergé Kubernetes avec DRBD + LINSTOR"
date: 2026-04-01
summary: "Construire un stockage distribué performant et hautement disponible pour Kubernetes dans un homelab"
tags: ["Kubernetes", "Storage", "DevOps", "Homelab"]
categories: ["Infrastructures"]
featuredImage: "featured.png"
-----------------------------

# 🏠 Introduction

Quand on commence à monter un cluster Kubernetes multi-nœuds, on tombe très vite sur un sujet critique : **le stockage**.

Comment trouver le bon compromis entre :
* ⚡ Performance (notamment pour les bases de données)
* 🔁 Haute disponibilité
* 💸 Coût raisonnable

Dans mon homelab sous Talos (dont je parle dans un autre article), mes workloads nécessitent un stockage **rapide et résilient**

Alors oui, j’aurais pu partir sur un simple NFS :
* Rapide à mettre en place ✅
* Mais limité en performance ❌
* Et surtout… beaucoup moins fun 😄

J’ai donc fait un choix plus intéressant techniquement : **une architecture hyperconvergée basée sur DRBD + LINSTOR**.

---

# 🗄️ SAN vs Hyperconvergé : deux philosophies

## 🏢 Le SAN : approche traditionnelle

Un **SAN (Storage Area Network)** est un réseau dédié au stockage

Concrètement, une baie de disques centralisée est exposée à plusieurs serveurs via : Fibre Channe ou SCSI

```
┌─────────┐     FC / iSCSI     ┌──────────────┐
│ Serveur │◄──────────────────►│ Baie de      │
│ Serveur │◄──────────────────►│ stockage SAN │
│ Serveur │◄──────────────────►│              │
└─────────┘                    └──────────────┘
```

### ✅ Avantages

* Très performant
* Mature et robuste
* Et c'est vraiment le standard en entreprise

### Les Inconvénients (surtout en homelab)

* 💸 Coût élevé (Il faut souvent payer du matériel propriétére / licences )
* 🔌 Point de défaillance unique sur le réseaux (Il faut doubler a chaque fois le réseaux pour éviter un SPOF)
* ⚙️ Complexité importante, c'est vraiment un métier a part entiere

---

## 🧱 L’hyperconvergé : approche moderne

Alors qu'une infrastructure **hyperconvergée (HCI)** fusionne :

* compute (CPU / RAM)
* stockage

Chaque nœud contribue avec ses **disques locaux**, et les données sont **répliquées via le réseau**.

```
┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐
│  Nœud 1          │   │  Nœud 2          │   │  Nœud 3          │
│  CPU + RAM       │   │  CPU + RAM       │   │  CPU + RAM       │
│  Disques locaux  │◄─►│  Disques locaux  │◄─►│  Disques locaux  │
└──────────────────┘   └──────────────────┘   └──────────────────┘
└──────────────── réplication DRBD ──────────────────┘
```

### ✅ Avantages

* Pas de matériel dédié
* Haute disponibilité native
* Scalabilité horizontale (Si on as besoin de plus de disque ou de CPU/RAM il suffit de rajouter une VM)
* Coût maîtrisé (Il n'y as pas d'autre cout que le compute/licence)

👉 C’est exactement ce que je recherchais.

Et la brique clé ici : **DRBD**

---

# 💾 DRBD + LVM thin : la couche stockage

## 🔁 DRBD : du RAID 1… sur le réseau

**DRBD (Distributed Replicated Block Device)** permet de répliquer un device bloc entre plusieurs machines.

👉 Conceptuellement :

> C’est un RAID 1 distribué sur le réseau

Chaque nœud expose un device :

```
/dev/drbd1000
```

Derrière :

```
Nœud 1              Nœud 2
/dev/drbd1000 ◄──► /dev/drbd1000
   │                    │
 /dev/sdb            /dev/sdb
```

### 🔑 Points clés

* Réplication synchrone ou asynchrone
* Mode Primary / Secondary
* Intégré avec Kubernetes via LINSTOR CSI

👉 Résultat : Kubernetes place automatiquement les pods **là où le volume est accessible**.

---

## 📦 LVM : thick vs thin

Avant de parler Kubernetes, il faut comprendre un point crucial côté stockage.

### 🧱 LVM Thick (provisionnement épais)

* L’espace est réservé immédiatement
* Exemple : LV de 10 Gi = 10 Gi consommés

👉 Simple, mais peu flexible

---

### 🧪 LVM Thin (provisionnement fin)

* Création d’un thin pool
* Allocation à la demande

👉 Tu peux créer 100 Gi… sans les consommer réellement

---

## ⚠️ Retour d’expérience (REX)

Au départ, j’étais en **LVM thick**.

Mais problème 👇

❌ Pas de support des snapshots CSI
❌ Impossible d’utiliser Velero efficacement
❌ Backup uniquement applicatif ou filesystem (lent + incohérent)

👉 J’ai donc migré vers **LVM thin**

### ✅ Résultat

* Snapshots fonctionnels
* Intégration parfaite avec Kubernetes
* Backup cohérent et rapide

---

# ⚙️ LINSTOR : le cerveau du stockage

**LINSTOR** est la couche qui orchestre DRBD.

Il permet de :

* créer des volumes distribués
* gérer la réplication
* exposer un CSI driver Kubernetes

👉 En gros : **il rend DRBD utilisable dans Kubernetes**

---

# ☸️ Intégration Kubernetes (Talos)

## 🧩 Architecture finale

* DRBD → réplication
* LVM thin → gestion des volumes
* LINSTOR → orchestration
* CSI → intégration Kubernetes

---

## 🚀 Déploiement dans Kubernetes

### 1. Installation LINSTOR

```bash
helm repo add linstor https://charts.linstor.io
helm install linstor linstor/linstor
```

---

### 2. Création d’un StorageClass

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: linstor-rwo
provisioner: linstor.csi.linbit.com
parameters:
  storagePool: lvm-thin
  placementCount: "2"
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
```

### 🔍 Explication

* placementCount: 2 → réplication sur 2 nœuds
* WaitForFirstConsumer → placement intelligent des pods

---

### 3. Création d’un PVC

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-data
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: linstor-rwo
  resources:
    requests:
      storage: 10Gi
```

---

### 4. Résultat

Quand ton pod démarre :

* volume créé automatiquement
* répliqué via DRBD
* attaché au bon nœud

👉 Transparence totale côté Kubernetes

---

# 📊 Pourquoi ce choix est parfait pour un homelab

## ✅ Ce que j’y gagne

* Haute dispo réelle
* Performances proches du local disk
* Scalabilité simple
* Zéro matériel dédié

## ❌ Les compromis

* Réseau critique (latence importante)
* Complexité supérieure à NFS
* Nécessite un minimum de tuning

---

# ✅ Conclusion

Avec cette stack **DRBD + LINSTOR + LVM thin**, j’ai construit un stockage :

* ⚡ performant
* 🔁 hautement disponible
* 🧠 parfaitement intégré à Kubernetes

👉 C’est clairement un game changer dans un homelab.

On se rapproche énormément des architectures enterprise… sans le coût.

Et surtout :

> c’est beaucoup plus fun qu’un NFS 😄
