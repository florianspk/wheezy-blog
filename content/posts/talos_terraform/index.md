---
title: "Talos + Terraform = ♥️"
date: 2025-08-05
summary: "Mon retour d'expérience sur Talos avec Terraform"
tags: ["Talos", "Kubernetes", "Terraform", "Infrastructure-as-Code", "Homelab"]
featuredImage: "featured.png"
---

{{< alert icon="💡" title="À noter" >}}
Même si je parle ici de **Terraform**, tout ce que je présente fonctionnerait également avec **OpenTofu**, sans modification.
{{< /alert >}}

# Introduction

Depuis quelques mois, je m'intéresse de près à **Talos**, un système d'exploitation minimaliste conçu spécifiquement pour Kubernetes.

J’ai installé mon premier cluster Talos en **décembre 2024**, et depuis, ma "production" — composée de deux serveurs physiques sous **Proxmox** — tourne avec cette stack.

Après plusieurs mois d’expérimentation, j’ai décidé de partager mon retour d’expérience, notamment sur l'intégration de **Talos avec Terraform** pour provisionner et gérer mes clusters de manière déclarative.

---

## 🤖 Qu'est-ce que Talos ?

**Talos** est un OS Linux immuable, ultra-minimaliste, et totalement dédié à Kubernetes.
Oubliez les distributions classiques : pas de shell, pas de package manager, pas de surface d’attaque inutile.

Ce design épuré apporte plusieurs avantages :

- ⚡️ Installation rapide et automatisable d’un nœud Kubernetes
- 🔐 Administration uniquement via une **API dédiée**, avec l’outil `talosctl`

Même sans SSH, `talosctl` permet de tout gérer :

- 📜 Accès aux logs système
- 🌐 Collecte de rapports réseau (`pcap`)
- 🩺 Diagnostic de l’état des nœuds
- 🔄 Mises à jour du système en mode déclaratif

**SideroLabs**, l’entreprise derrière Talos, fournit une excellente documentation, et la communauté est active. C’est un projet mature, adopté en production par de nombreuses organisations.

---

## 🏗️ Pourquoi Terraform avec Talos ?

J’utilise **Terraform** pour provisionner mes VM sur Proxmox. Alors je me suis dit : *“Pourquoi ne pas aller plus loin et gérer aussi les configs Talos avec Terraform ?”*

L’objectif : automatiser **tout** le cycle de vie du cluster, du boot au déploiement des applications.

Ce que cette approche m’apporte :

- 🔧 **Versionner** toutes mes configurations dans Git
- 📦 **Intégrer mes charts Helm** dès l'initialisation
- 🚀 **Bootstrap automatique** du cluster
- 🔁 **Déploiement reproductible**, même après un wipe complet

L’idée, c’est d’avoir un cluster Kubernetes **production-ready dès le premier boot** :
avec `Cilium`, `ArgoCD`, la gestion des certificats et mes outils préférés déjà en place.

---


# 🛠️ Setup de Talos sans terraform

On vas rentrer dans le vif du sujet maintenant, comment j'ai vu les choses et comment un bootstrappe d'un cluster talos sans terraform
La commande `talosctl gen config talos-proxmox-cluster https://$CONTROL_PLANE_IP:6443 --output-dir _out` génère une configuration complète pour un cluster Talos.
Voici les fichiers que nous allons retrouver dans `_out/` :
- `controlplane.yaml` - Configuration pour les nœuds control plane
- `worker.yaml` - Configuration pour les nœuds worker
- `talosconfig` - Fichier de configuration client pour talosctl

des certificats et mes outils préférés directement intégrés.

---

# 🛠️ Setup de Talos sans Terraform

On rentre maintenant dans le vif du sujet : comment booter un cluster Talos manuellement, sans Terraform.

La commande suivante génère les fichiers de configuration pour un cluster Talos :

```bash
talosctl gen config talos-proxmox-cluster https://$CONTROL_PLANE_IP:6443 --output-dir _out
```

Dans le dossier `_out/`, on retrouve :

- `controlplane.yaml` — Configuration des nœuds control plane
- `worker.yaml` — Configuration des nœuds worker
- `talosconfig` — Fichier client pour `talosctl`

---

## ✍️ Champs importants de la configuration

### 1. Configuration du cluster

```yaml
cluster:
  clusterName: talos-proxmox-cluster
  controlPlane:
    endpoint: https://$CONTROL_PLANE_IP:6443
  network:
    dnsDomain: cluster.local
    podSubnets:
      - 10.244.0.0/16
    serviceSubnets:
      - 10.96.0.0/12
```

### 2. Configuration machine

```yaml
machine:
  type: controlplane # ou worker
  token: wNf8GvZz... # Token d'authentification machine
  ca:
    crt: LS0tLS1CRU... # Certificat CA root du cluster
    key: LS0tLS1CRU... # Clé privée CA (sensible!)
  certSANs:
    - $CONTROL_PLANE_IP
  kubelet:
    image: ghcr.io/siderolabs/kubelet:v1.x.x
```

---

## 🧩 inlineManifests : Déploiement dès le bootstrap

Les `inlineManifests` permettent d’appliquer des manifests Kubernetes **dès le démarrage du cluster**. Parfait pour automatiser le bootstrap.

Exemple :

```yaml
cluster:
  inlineManifests:
    - name: "flannel"
      contents: |
        ---
        apiVersion: apps/v1
        kind: DaemonSet
        metadata:
          name: kube-flannel-ds
          namespace: kube-system
        spec:
          ...
```

---

# 📦 Le truc magique : les Inline Manifests (avec Terraform cette fois !)

Comme vu plus haut, les `inlineManifests` sont une feature géniale. L’idée maintenant est de **générer dynamiquement** ces manifests via Terraform et Helm.

---

## 🌐 Providers Terraform utilisés

Dans ce projet, j’utilise deux providers :

- `talos` — pour créer les configs machines Talos
- `helm` — pour templater les charts Helm comme Cilium ou ArgoCD

```hcl
terraform {
  required_version = ">= 1.10.0"
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "0.8.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.0.2"
    }
  }
}
```

---

## 🔌 Provisionnement de Cilium avec Helm + Terraform

J’utilise **Cilium** comme CNI. Voici comment je définis les manifests dans `cilium.tf` :

```hcl
locals {
  cilium_manifest_objects = [
    # Création d'un objet CiliumL2AnnouncementPolicy non possible dans la chart helm
    {
      apiVersion = "cilium.io/v2alpha1"
      kind       = "CiliumL2AnnouncementPolicy"
      metadata = {
        name = "external"
      }
      spec = {
        loadBalancerIPs = true
        interfaces = ["eth0"]
        nodeSelector = {
          matchExpressions = [
            {
              key      = "node-role.kubernetes.io/control-plane"
              operator = "DoesNotExist"
            }
          ]
        }
      }
    },
    {
      apiVersion = "cilium.io/v2alpha1"
      kind       = "CiliumLoadBalancerIPPool"
      metadata = {
        name = "external"
      }
      spec = {
        blocks = [
          {
            start = cidrhost("10.10.1.1", 10)
            stop  = cidrhost("10.10.1.1", 15)
          }
        ]
      }
    }
  ]
  cilium_external_lb_manifest = join("---\n", [for d in local.cilium_manifest_objects : yamlencode(d)])
}
# C'est ici que se passe mon helm template
data "helm_template" "cilium" {
  namespace    = "kube-system"
  name         = "cilium"
  repository   = "https://helm.cilium.io"
  chart        = "cilium"
  version      = "1.18.0"
  kube_version = var.kubernetes_version
  values       = [file("${path.module}/helm/cilium-values.yaml")]
}
```

---

# 🧱 Bootstrap des machine configs avec Terraform

Dans un fichier `talos.tf`, je définis la configuration des machines control planes et workers :

```hcl
resource "talos_machine_secrets" "talos" {
  talos_version = "v${var.talos_version}"
}

data "talos_machine_configuration" "controller" {
  ...
  # On peut meme lui passer des configs patches
  config_patches = [
    yamlencode(local.common_machine_config),
    yamlencode({
      machine = {
        network = {
          interfaces = [{
            interface = "eth0"
            vip = {
              ip = var.cluster_vip
            }
          }]
        }
      }
    }),
    yamlencode({
      cluster = {
        # Ici le fameux Block inlineManifests qui va me permettre d'appeler mes manifests générés juste avant
        inlineManifests = concat([
          {
            name     = "cilium"
            contents = join("---\n", [
              data.helm_template.cilium.manifest,
              "# Source cilium.tf\n${local.cilium_external_lb_manifest}",
            ])
          }
        ])
      }
    })
  ]
}
```

Et les ressources pour appliquer la configuration aux machines :

```hcl

resource "talos_machine_configuration_apply" "controller" {
  count                       = var.controller_count #Nombre de contrôleurs
  client_configuration        = talos_machine_secrets.talos.client_configuration #La config talos généré au début
  machine_configuration_input = data.talos_machine_configuration.controller.machine_configuration # le fichier machine configuration que nous avons généré juste au dessus
  endpoint                    = local.controller_nodes[count.index].address # Le endpoint talos
  node                        = local.controller_nodes[count.index].address # Le noeud en question ou on fait un apply
  # Ici je remets 2 patch pour la config DNS et NTP
  config_patches = [
    yamlencode({
      machine = {
        network = {
          hostname    = local.controller_nodes[count.index].name
          nameservers = var.dns_serveurs
        }
        time = {
          servers = var.ntp_serveurs
        }
      }
    }),
  ]
}

# Exactement comme le bloc au dessus mais la en précisant les workers
resource "talos_machine_configuration_apply" "worker" {
  count                       = var.worker_count
  client_configuration        = talos_machine_secrets.talos.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  endpoint                    = local.worker_nodes[count.index].address
  node                        = local.worker_nodes[count.index].address
  config_patches = [
    yamlencode({
      machine = {
        network = {
          hostname    = local.worker_nodes[count.index].name
          nameservers = var.dns_serveurs
        }
        time = {
          servers = var.ntp_serveurs
        }
      }
    }),
  ]
}

```

---

# 🔧 Upgrade du cluster via Terraform

## 🆙 Comment je gère les upgrades

La gestion des versions est simplissime. Dans mes variables :

```hcl
variable "kubernetes_version" {
  description = "Version de Kubernetes"
  type        = string
  default     = "v1.33.3"
}
```

Je change la version, je `terraform apply`, et Talos détecte la différence. C’est tout.

## ✅ Mon retour d’expérience

Ce que j’adore :

- Mise à jour **automatisée et progressive**
- **Pas de downtime**
- Possibilité de **rollback**
- Terraform garde **l’état à jour**

### Points de vigilance

- Lire les **release notes**
- Tester sur un cluster **de dev**
- Toujours **backuper les configs**
- **Observer les logs** pendant l’upgrade

---

# 📁 Mon Homelab

Tout est référencé dans le dépôt GitHub ci dessous, n'hésitez pas y jetez un œil et une star ⭐️ fait toujours plaisir !

{{< github repo="florianspk/home-lab-talos" >}}

---

# 🎉 Bilan après 1 an avec Talos

## ✅ Les points positifs

- **Simplicité** : pas d’OS à configurer
- **Sécurité** : système immuable et minimal
- **API-first** : tout passe par `talosctl`
- **Upgrades** sans stress
- Intégration **Terraform + Helm** au top

## 🤔 Quelques bémols

- **Courbe d’apprentissage** (pas de shell…)
- **Debug** parfois moins évident

## 🚀 Mes conseils

- Testez Talos sur un petit cluster
- Gérez vos configs avec Terraform
- Intégrez vos charts Helm dès le début

Cette stack **Talos + Terraform + Helm** m’a vraiment simplifié la vie.

**Prochaine étape** : creuser **Omni**, l’outil de gestion des clusters Talos par SideroLabs 🎯
