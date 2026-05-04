---

title: "Stockage hyperconvergé Kubernetes avec DRBD + LINSTOR"
date: 2026-05-03
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
* Coût maîtrisé (Il n'y as pas d'autre cout que le compute)

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

**LINSTOR** est la couche d’orchestration qui pilote **DRBD**.

Concrètement, il permet de :

* provisionner des volumes distribués
* gérer automatiquement la réplication
* exposer un driver CSI pour Kubernetes

👉 En résumé : **il transforme DRBD en solution de stockage exploitable dans Kubernetes**

---

# ☸️ Intégration Kubernetes

## 🧩 Architecture globale

La stack repose sur plusieurs briques complémentaires :

* **DRBD** → réplication des données entre nœuds
* **LVM thin** → gestion des volumes et thin provisioning
* **LINSTOR** → orchestration du stockage
* **CSI** → intégration native avec Kubernetes

---

## 🚀 Déploiement dans Kubernetes

### 1. Installation de Piraeus (LINSTOR pour Kubernetes)

Dans Kubernetes, on ne déploie pas LINSTOR “à la main”.
On passe par Piraeus Operator, qui automatise toute l’installation.

```bash
helm repo add linstor https://charts.linstor.io
helm install piraeus linstor/linstor
```

👉 Cela déploie automatiquement :

* LINSTOR Controller
* LINSTOR Satellites
* le CSI driver
* toute la glue Kubernetes

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

* `placementCount: 2` → réplique le volume sur 2 nœuds
* `storagePool` → Le type de storage

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

Au démarrage du pod :

* le volume est provisionné automatiquement
* les données sont répliquées via DRBD
* le volume est attaché au nœud optimal

👉 Tout est **transparent côté Kubernetes**

---

# 📊 Pourquoi ce choix est idéal en homelab

## ✅ Les avantages

* Haute disponibilité réelle (pas du pseudo-HA)
* Performances proches d’un disque local
* Scalabilité horizontale simple
* Aucun besoin de matériel dédié

## ❌ Les compromis

* Le réseau devient critique (latence et débit)
* Plus complexe qu’un simple NFS
* Nécessite un peu de tuning (DRBD, scheduler, etc.)

---

# ✅ Conclusion

Avec la stack **DRBD + LINSTOR + LVM thin**, on obtient un stockage :

* ⚡ performant
* 🔁 résilient
* 🧠 totalement intégré à Kubernetes

On se rapproche clairement des standards **enterprise**, sans en avoir le coût… ni la rigidité.

Et surtout :

> c’est quand même beaucoup plus fun qu’un NFS 😄
