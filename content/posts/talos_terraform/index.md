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

J'ai installé mon premier cluster Talos en **décembre 2024**, et depuis, ma "production" — composée de deux serveurs physiques sous **Proxmox** — tourne avec cette stack.

Après plusieurs mois d'expérimentation, j'ai décidé de partager mon retour d'expérience, notamment sur l'intégration de **Talos avec Terraform** pour provisionner et gérer mes clusters de manière déclarative.

---

## 🤖 Qu'est-ce que Talos ?

**Talos** est un OS Linux immuable, ultra-minimaliste, et totalement dédié à Kubernetes.
Oubliez les distributions classiques : pas de shell, pas de package manager, pas de surface d'attaque inutile.

Imaginez un OS qui démarre directement avec Kubernetes préconfiguré ! C'est exactement ça Talos. Pas besoin d'installer Docker, containerd, ou de configurer systemd — tout est déjà intégré et optimisé.

Ce design épuré apporte plusieurs avantages :

- ⚡️ **Installation en quelques minutes** : plus besoin de passer des heures à configurer chaque nœud
- 🔐 **Administration uniquement via une API dédiée** : fini les connexions SSH hasardeuses
- 🛡️ **Sécurité renforcée** : surface d'attaque minimale, système en lecture seule

Même sans SSH, l'outil `talosctl` permet de tout gérer à distance :

- 📜 Accès aux logs système (comme `journalctl` mais en mieux)
- 🌐 Collecte de rapports réseau (`pcap` pour débugger les problèmes réseau)
- 🩺 Diagnostic complet de l'état des nœuds
- 🔄 Mises à jour du système en mode déclaratif (comme Kubernetes !)

**SideroLabs**, l'entreprise derrière Talos, fournit une excellente documentation, et la communauté est active. C'est un projet mature, adopté en production par de nombreuses organisations — pas juste un jouet pour homelab !

---

## 🏗️ Pourquoi Terraform avec Talos ?

J'utilisais déjà **Terraform** pour provisionner mes VMs sur Proxmox. Alors je me suis dit : *"Pourquoi ne pas aller plus loin et gérer aussi les configs Talos avec Terraform ?"*

L'idée peut paraître folle au début — après tout, Talos a déjà ses propres outils. Mais en réalité, cette approche révolutionne complètement le workflow !

L'objectif : automatiser **tout** le cycle de vie du cluster, du boot au déploiement des applications.

Ce que cette approche m'apporte concrètement :

- 🔧 **Versionner** toutes mes configurations dans Git (exit les fichiers YAML éparpillés partout)
- 📦 **Intégrer mes charts Helm** dès l'initialisation (Cilium, ArgoCD, cert-manager... tout en une fois)
- 🚀 **Bootstrap automatique** du cluster (démarrage complètement mains libres)
- 🔁 **Déploiement reproductible** à 100% (même après un wipe complet du homelab à 2h du matin)

L'idée, c'est d'avoir un cluster Kubernetes **production-ready dès le premier boot** :
avec `Cilium` comme CNI, `ArgoCD` pour le GitOps, la gestion des certificats SSL et tous mes outils préférés déjà en place. Plus besoin de se rappeler dans quel ordre installer quoi !

---

# 🛠️ Setup de Talos sans Terraform

Avant de plonger dans la magie Terraform, voyons comment Talos fonctionne "à la main". C'est important de comprendre les bases !

Pour bootstrapper un cluster Talos classiquement, on utilise cette commande :

```bash
talosctl gen config talos-proxmox-cluster https://$CONTROL_PLANE_IP:6443 --output-dir _out
```

**Décortiquons cette commande :**
- `talos-proxmox-cluster` : le nom de votre cluster (choisissez quelque chose de parlant !)
- `https://$CONTROL_PLANE_IP:6443` : l'URL où sera accessible l'API Kubernetes (remplacez par votre IP)
- `--output-dir _out` : le dossier où seront générés tous les fichiers

Dans le dossier `_out/`, on retrouve trois fichiers essentiels :

- `controlplane.yaml` — La recette pour cuisiner vos nœuds control plane
- `worker.yaml` — La configuration des nœuds worker (les petites mains du cluster)
- `talosconfig` — Votre passe-partout pour parler avec `talosctl`

Ces fichiers contiennent **tous les secrets** de votre cluster : certificats, clés, tokens... À garder précieusement !

---

## ✍️ Champs importants de la configuration

Rentrons dans le vif du sujet ! Voici les sections cruciales de la config Talos :

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

**Explications :**
- `clusterName` : le petit nom de votre cluster (sera visible dans `kubectl config`)
- `endpoint` : l'adresse pour accéder à l'API Kubernetes depuis l'extérieur
- `dnsDomain` : le suffixe DNS interne (généralement `cluster.local`)
- `podSubnets` : le réseau où vivront vos pods (pensez à ne pas avoir de conflit avec votre LAN !)
- `serviceSubnets` : le réseau pour les services Kubernetes

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

**Ce qui se passe ici :**
- `type` : définit le rôle de la machine (controlplane = chef d'orchestre, worker = exécutant)
- `token` : un secret partagé pour que les machines puissent se reconnaître
- `ca.crt` et `ca.key` : les certificats racine du cluster (à protéger comme la prunelle de vos yeux !)
- `certSANs` : les adresses IP/DNS autorisées pour l'API (important pour éviter les erreurs de certificats)
- `kubelet.image` : la version du kubelet à utiliser

---

## 🧩 inlineManifests : La magie du déploiement automatique

Les `inlineManifests` sont **LA feature killer** de Talos ! Ils permettent d'appliquer des manifests Kubernetes **dès le démarrage du cluster**.

Concrètement ? Votre cluster démarre avec Cilium, ArgoCD et tous vos outils déjà installés. Plus besoin de faire 15 `kubectl apply` après chaque bootstrap !

Voici un exemple basique avec Flannel (CNI réseau) :

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
          selector:
            matchLabels:
              app: flannel
          # ... reste de la config Flannel
```

**Comment ça marche ?**
1. Talos démarre et initialise Kubernetes
2. Dès que l'API est disponible, il applique automatiquement tous les `inlineManifests`
3. Votre cluster est immédiatement opérationnel avec votre stack préférée !

L'avantage énorme : **reproductibilité totale**. Chaque fois que vous bootstrappez le cluster, vous obtenez exactement la même chose.

---

# 📦 Le truc magique : les Inline Manifests (avec Terraform cette fois !)

Maintenant qu'on a vu les bases, passons au niveau supérieur ! L'idée géniale est de **générer dynamiquement** ces manifests via Terraform et Helm.

Au lieu d'écrire à la main des centaines de lignes YAML (bonjour l'enfer de la maintenance), on va laisser Helm faire le boulot et Terraform orchestrer le tout.

---

## 🌐 Providers Terraform utilisés

Pour cette aventure, j'ai besoin de deux providers Terraform :

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

**Pourquoi ces deux-là ?**

- **Provider `talos`** : créé par SideroLabs eux-mêmes, il permet de générer les configs machines Talos directement dans Terraform
- **Provider `helm`** : pour templater les charts Helm comme Cilium ou ArgoCD **sans déployer** (on veut juste récupérer le YAML final)

Cette combinaison est magique : Helm génère le YAML parfait pour chaque chart, et le provider Talos l'injecte dans les `inlineManifests` !

---

## 🔌 Provisionnement de Cilium avec Helm + Terraform

**Cilium** est mon CNI de choix (Container Network Interface). C'est lui qui gère le réseau entre les pods et les services Kubernetes. Voici comment je l'intègre dans mes configs Talos :

```hcl
locals {
  # Quelques manifests personnalisés que Helm ne peut pas générer
  cilium_manifest_objects = [
    # Load Balancer pour exposer des services sur mon LAN
    {
      apiVersion = "cilium.io/v2alpha1"
      kind       = "CiliumL2AnnouncementPolicy"
      metadata = {
        name = "external"
      }
      spec = {
        loadBalancerIPs = true
        interfaces = ["eth0"]
        # Seuls les workers peuvent annoncer les IPs (pas les control planes)
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
    # Pool d'IPs disponibles pour le load balancer
    {
      apiVersion = "cilium.io/v2alpha1"
      kind       = "CiliumLoadBalancerIPPool"
      metadata = {
        name = "external"
      }
      spec = {
        blocks = [
          {
            start = "10.10.1.10"  # Première IP disponible
            stop  = "10.10.1.15"  # Dernière IP disponible
          }
        ]
      }
    }
  ]
  # Conversion en YAML pour les inlineManifests
  cilium_external_lb_manifest = join("---\n", [for d in local.cilium_manifest_objects : yamlencode(d)])
}

# La magie : Helm génère le manifest Cilium complet
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

**Ce qui se passe ici :**

1. **Les `locals`** : je définis des ressources Cilium spécifiques que la chart Helm standard ne gère pas (comme le load balancer L2)
2. **Le `data "helm_template"`** : Terraform demande à Helm de générer tout le YAML de Cilium, mais **sans le déployer**
3. **Les `values`** : j'utilise un fichier `cilium-values.yaml` pour personnaliser Cilium (activation de Hubble, configuration réseau, etc.)

Le résultat ? Un YAML parfait, testé par la communauté Cilium, mais personnalisé pour mon environnement !

---

# 🧱 Bootstrap des machine configs avec Terraform

Maintenant, le plat de résistance ! Voici comment je génère les configurations Talos avec Terraform :

```hcl
resource "talos_machine_secrets" "talos" {
  talos_version = "v${var.talos_version}"
}
```

Cette ressource génère **tous les secrets** nécessaires au cluster : certificats CA, tokens d'authentification, clés de chiffrement... C'est l'équivalent de ce que fait `talosctl gen config` mais dans Terraform.

Ensuite, je définis la configuration des control planes :

```hcl
data "talos_machine_configuration" "controller" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.cluster_vip}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.talos.machine_secrets

  # Configuration réseau de base commune à toutes les machines
  config_patches = [
    yamlencode(local.common_machine_config),
    # Configuration spécifique aux control planes : VIP pour haute dispo
    yamlencode({
      machine = {
        network = {
          interfaces = [{
            interface = "eth0"
            vip = {
              ip = var.cluster_vip  # IP virtuelle partagée entre les control planes
            }
          }]
        }
      }
    }),
    # LE GROS MORCEAU : les inlineManifests avec Cilium
    yamlencode({
      cluster = {
        inlineManifests = [
          {
            name     = "cilium"
            contents = join("---\n", [
              data.helm_template.cilium.manifest,  # Le YAML généré par Helm
              "# Configuration load balancer personnalisée\n${local.cilium_external_lb_manifest}",
            ])
          }
        ]
      }
    })
  ]
}
```

**Décryptage :**
- `cluster_endpoint` : l'adresse VIP (Virtual IP) partagée entre tous les control planes
- `config_patches` : des modifications YAML appliquées par-dessus la config de base
- La **VIP** permet d'avoir plusieurs control planes derrière une même IP (haute disponibilité)
- Les **`inlineManifests`** injectent directement le YAML de Cilium dans la config Talos

Et maintenant, l'application de ces configurations sur les vraies machines :

```hcl
# Application de la config sur chaque control plane
resource "talos_machine_configuration_apply" "controller" {
  count                       = var.controller_count
  client_configuration        = talos_machine_secrets.talos.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controller.machine_configuration
  endpoint                    = local.controller_nodes[count.index].address
  node                        = local.controller_nodes[count.index].address

  # Patch spécifique à chaque machine (hostname, DNS, NTP)
  config_patches = [
    yamlencode({
      machine = {
        network = {
          hostname    = local.controller_nodes[count.index].name  # talos-cp-01, talos-cp-02, etc.
          nameservers = var.dns_serveurs                          # Mes DNS locaux
        }
        time = {
          servers = var.ntp_serveurs                              # Serveurs NTP pour la sync
        }
      }
    }),
  ]
}

# Même chose pour les workers (mais sans la VIP et les inlineManifests)
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

**Ce qui se passe concrètement :**
1. Terraform génère la config Talos avec Cilium intégré
2. Pour chaque machine, il applique cette config + des patches spécifiques (nom, DNS, NTP)
3. Chaque nœud redémarre avec sa nouvelle configuration
4. Au boot, Talos applique automatiquement Cilium via les `inlineManifests`
5. Le cluster est opérationnel avec le réseau configuré !

---

# 🔧 Upgrade du cluster via Terraform

## 🆙 Comment je gère les upgrades

Fini les upgrades qui donnent des sueurs froides ! Avec Terraform + Talos, c'est d'une simplicité déconcertante.

Dans mon fichier de variables, j'ai juste ça :

```hcl
variable "kubernetes_version" {
  description = "Version de Kubernetes à déployer"
  type        = string
  default     = "v1.33.3"
}
```

**Le workflow d'upgrade :**
1. Je change la version dans ma variable : `v1.33.2` → `v1.33.3`
2. Je lance `terraform plan` pour voir ce qui va changer
3. Je fais `terraform apply`
4. Talos détecte automatiquement la différence de version
5. Il upgrade nœud par nœud, en rolling update

C'est tout ! Pas de script bash chelou, pas de commandes à retenir, pas de risque d'oublier un nœud.

## ✅ Mon retour d'expérience après de nombreuses upgrades

**Ce que j'adore dans cette approche :**

- **Mise à jour progressive et automatisée** : Talos upgrade un nœud à la fois, attend qu'il soit stable, puis passe au suivant
- **Zero downtime** : avec plusieurs control planes et workers, mes applications continuent de tourner
- **Rollback facile** : si ça part en vrille, je repasse à l'ancienne version et `terraform apply`
- **Terraform garde l'état à jour** : plus jamais de désynchronisation entre mes fichiers et la réalité

**Un exemple concret :**
J'ai récemment upgradé de Kubernetes 1.32 à 1.33. Le processus a pris environ 20 minutes pour un cluster de 5 nœuds, et je n'ai eu aucune interruption de service sur mes applications.

### ⚠️ Points de vigilance (j'ai appris à mes dépens)

- **Toujours lire les release notes** : parfois il y a des breaking changes (surtout entre versions majeures)
- **Tester sur un cluster de dev d'abord** : Ca peut se faire trés simplement en local
- **Sauvegarder les configs avant** : `git commit` de toutes vos configurations Terraform
- **Observer les logs pendant l'upgrade** : `talosctl logs -f` sur chaque nœud pour voir si tout se passe bien
- **Prévoir du temps** : même si c'est automatisé, restez dispo pour surveiller

---

# 📁 Mon Homelab en pratique

Si vous voulez voir tout ça en action, j'ai mis **tout mon code** en open source ! Vous y trouverez :

- Les configurations Terraform complètes
- Les fichiers de values Helm pour chaque chart
- Mes scripts d'automatisation
- La documentation pour reproduire chez vous

{{< github repo="florianspk/home-lab-talos" >}}

**Ce que vous y trouverez concrètement :**
- Configuration Proxmox + Terraform pour créer les VMs
- Bootstrap complet Talos avec Cilium, ArgoCD, cert-manager
- Ingress avec Traefik et certificats SSL auto
- Exemples d'applications déployées via GitOps

N'hésitez pas à y jeter un œil et une star ⭐️ fait toujours plaisir (et aide d'autres personnes à découvrir le projet) !

---

# 🎉 Bilan après 1 an avec Talos + Terraform

## ✅ Les points positifs (et il y en a beaucoup !)

- **Simplicité déconcertante** : plus d'OS à patcher, configurer, maintenir
- **Sécurité renforcée** : système immuable, surface d'attaque minimale, pas de shell
- **Administration moderne** : tout passe par l'API avec `talosctl` (finies les connexions SSH hasardeuses)
- **Upgrades sans stress** : rolling updates automatiques, rollback facile
- **Intégration Terraform + Helm au top** : Infrastructure as Code poussée à son maximum
- **Reproductibilité parfaite** : je peux reconstruire mon cluster identique en 30 minutes
- **Communauté active** : documentation excellente, support réactif

## 🤔 Quelques bémols (soyons honnêtes)

- **Courbe d'apprentissage** : passer du SSH traditionnel à l'API-only demande un changement d'habitudes
- **Debug parfois moins évident** : quand quelque chose ne va pas, il faut apprendre les outils spécifiques à Talos
- **Écosystème encore jeune** : moins de tutos et d'exemples que pour du Kubernetes avec kubeadm ou autre

## 🚀 Mes conseils pour bien commencer

1. **Testez d'abord sur un petit cluster** : 1 control plane + 1 worker dans des VMs
2. **Maîtrisez `talosctl`** : prenez le temps d'explorer toutes les commandes
3. **Gérez vos configs avec Terraform dès le début** : n'attendez pas d'avoir 10 clusters en manuel
4. **Intégrez vos charts Helm dans les inlineManifests** : c'est là que la magie opère

## 🔮 Et maintenant ?

Cette stack **Talos + Terraform + Helm** m'a vraiment révolutionné la gestion de mon/mes clusters. Mais je ne compte pas m'arrêter là !

**Prochaine étape** : creuser **Omni**, l'outil SaaS de gestion de clusters Talos par SideroLabs. L'idée : une interface web pour piloter tous mes clusters Talos, avec gestion des upgrades, monitoring intégré et déploiement multi-cloud.

Si vous vous lancez dans l'aventure Talos, n'hésitez pas à me faire un retour ! Je suis toujours curieux de voir comment d'autres personnes utilisent cette stack.
