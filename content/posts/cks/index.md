---
title: "CKS — Comment j'ai obtenu 91% à la Certified Kubernetes Security Specialist"
date: 2026-04-22
draft: false
tags: ["kubernetes", "cks", "certification", "devops", "sre", "securite"]
categories: ["Certifications"]
description: "Retour d'expérience complet sur la préparation et le passage de la CKS en 2026 : ressources, domaines clés, pièges à éviter et cheat sheet à télécharger."
cover:
  image: ""
  alt: "CKS Kubernetes Security Specialist"
---

Il y a quelques semaines, je décrochais la **Certified Kubernetes Security Specialist (CKS)** avec un score de **91%**. Pour cela deux semaines de préparation sérieuse, beaucoup de pratique, et quelques erreurs qui m'ont appris plus que n'importe quel cours.

Cet article est un retour d'expérience honnête, ce qui fonctionne vraiment, pourquoi certains domaines sont pièges, et comment j'ai structuré ma préparation.

---

## Qui je suis et pourquoi la CKS

Je travaille en tant qu'ingénieur SRE/DevOps depuis environ cinq ans. Au quotidien : migrations cloud, infrastructure Kubernetes, provisioning via Cluster API, déploiements GPU. La sécurité des clusters n'est pas un sujet théorique pour moi — c'est quelque chose que je gère en production.

J'avais déjà la **CKA** (prérequis obligatoire pour la CKS, sans elle vous ne pouvez pas vous inscrire) et j'exploite un homelab sous Talos Linux / Cilium depuis plusieurs années. J'avais donc déja de bonne base pour cette examen

Malgré ça, la CKS m'a demandé un mois de travail spécifique. Pas parce que les concepts sont inaccessibles, mais parce que **la sécurité Kubernetes a ses propres pièges**, ses intégrations complexes, et une façon bien particulière de casser silencieusement un cluster si on n'est pas précis.

---

## Format de l'examen : ce qu'il faut savoir

Avant de rentrer dans le vif du sujet, quelques rappels sur le format :

- **120 minutes**, environ 16 à 20 tâches pratiques
- **Score de passage : 67%** — la marge est là, mais elle se mange vite
- Entièrement **terminal-based**, avec un navigateur intégré pour la documentation officielle
- **Documentation autorisée** : Kubernetes, Falco, Istio, AppArmor — mais pas de temps à perdre à chercher
- Surveillance en ligne avec un proctor : pièce seule, passeport sur le bureau, pas de second écran

La documentation est là pour confirmer une syntaxe, pas pour apprendre un concept le jour J. Si vous cherchez à comprendre ce qu'est un `PeerAuthentication` Istio pendant l'exam, c'est déjà perdu.

---

## Comment je l'ai préparé :

### La base : trois ans de pratique avant même de commencer

Ce que je n'aurais pas dû sous-estimer, c'est à quel point mon homelab et mon expérience pro m'ont pré-mâché une grosse partie du travail. Gérer des `NetworkPolicy` en production avec Cilium, configurer des `securityContext` sur des workloads réels, déboguer des pods qui ne démarrent pas à cause d'un profil AppArmor mal appliqué — tout ça, je le faisais déjà. **La pratique quotidienne remplace difficilement n'importe quel cours.**

Si vous débutez sur Kubernetes, visez la CKA d'abord, faites tourner un vrai cluster quelques mois, puis revenez à la CKS.

### KillerCoda Labs : indispensable

Pour la CKA comme pour la CKS, avant de commencer les révisions j'ai commencer par faire les labs que propose killerCoda, des labs assez rapide a faire et qui nous mettes en condition réel

Pour la CKS les labs que j'ai le plus répété :
- **Falco** : modification de règles, rechargement, lecture des alertes
- **CIS Benchmarks** avec `kube-bench`
- **Chiffrement des Secrets dans etcd**
- **Activité syscall** avec `strace` et `falco`

### Killer.sh : les deux sessions, les deux tentatives

Avec l'achat de l'examen, vous avez deux sessions Killer.sh de 36h. Je les ai utilisées toutes les deux. Ces simulations sont **plus dures que l'examen réel** — c'est voulu. Si vous les finissez à 70-75%, vous êtes en bonne voie.

Mon conseil : activez la première session environ une semaine avant l'examen. Analysez **chaque tâche ratée** en détail. Activez la seconde 48h avant, cette fois en mode révision plutôt qu'en mode découverte.

### Le homelab comme terrain d'entraînement

J'ai utilisé un cluster provisionné grace a vagrant pour provisionner des labs rapidement pour tester des scénarios
Repo Github : https://github.com/florianspk/vagrant-kubeadm-kubernetes-debian

---

## Les domaines : ce qui compte et ce qui piège

### SecurityContext — la base, mais attention aux niveaux

C'est le domaine où les points se gagnent ou se perdent sur des détails. La configuration `runAsNonRoot`, `allowPrivilegeEscalation: false`, la gestion des capabilities Linux (`drop: ALL`, `add: NET_BIND_SERVICE`) — tout ça doit être su par cœur.

**Le piège classique** : appliquer la configuration au mauvais niveau. Un `securityContext` se pose au niveau du Pod et/ou du container,, attention donc a bien lire l'énoncé

### Falco — runtime security, pas si compliqué

Falco est présent dans la section "runtime security". Ce qui est testé : lire et comprendre des règles existantes, modifier une règle pour capturer un comportement spécifique, vérifier que les alertes sont bien générées.

La commande la plus utile pour valider une règle :

```bash
falco -r /etc/falco/rules.d/custom.yaml -U
```

Connaissez la syntaxe des champs (`proc.name`, `fd.name`, `user.name`, etc.) et la structure d'une règle avec `condition` et `output`.

### NetworkPolicy / CiliumNetworkPolicy — penser en flux

Les tâches de NetworkPolicy demandent souvent de mettre en place un **default deny** puis d'ouvrir précisément ce qui est nécessaire. L'erreur fréquente : oublier soit l'ingress soit l'egress, ou mal cibler avec `namespaceSelector` + `podSelector`.

Si vous utilisez Cilium en production comme moi, la `CiliumNetworkPolicy` suit la même logique mais avec une syntaxe légèrement différente — assurez-vous de ne pas mélanger les deux à l'examen selon le contexte donné.

Pour m'entrainer je me suis beaucoup aider de : https://editor.networkpolicy.io/

### Istio

Istio est au programme même si la majorité des gens ne l'utilisent pas en production. Ce qui est testé : activer le **mTLS strict** entre services via `PeerAuthentication`, et contrôler les accès L7 via `AuthorizationPolicy`.

La distinction clé à maîtriser :
- `PeerAuthentication` → authentification entre services (mTLS)
- `AuthorizationPolicy` → qui peut appeler quoi (L7 rules)

### Auditing

La configuration des audit logs Kubernetes demande de modifier le manifest de l'API server avec les bons flags (`--audit-policy-file`, `--audit-log-path`) et de monter les fichiers correctement. Le fichier de policy définit les niveaux (`None`, `Metadata`, `Request`, `RequestResponse`) par ressource et par verbe.

Encore une fois : backup du manifest avant modification, vérification du redémarrage après.

### RBAC, TLS Secrets, CIS Benchmarks, SBOM

Ces domaines sont plus directs mais consomment du temps si vous n'êtes pas fluide. `kube-bench` pour les CIS Benchmarks s'utilise comme suit :

```bash
kube-bench run --targets master --check 1.2.7
```

Pour les secrets TLS dans un Ingress :

```bash
kubectl create secret tls mon-secret --cert=cert.pem --key=key.pem -n mon-namespace
```

Pour les SBOM (Software Bill of Materials), connaissez `trivy` et les formats SPDX / CycloneDX.

---

## Gestion du temps : la compétence invisible

120 minutes pour 16-20 tâches, c'est serré. Ma stratégie :

1. **Premier passage** : je lis toutes les tâches rapidement, j'attaque dans l'ordre les tâches que je maîtrise
2. **Règle des 7 minutes** : si je suis bloqué sans progression visible après 7 minutes, je flag et je skip
3. **Retour en fin de session** : je reviens sur les tâches skippées avec le temps restant

Ce qui semble contre-intuitif mais est essentiel : **une tâche à 4% que vous bloquez 20 minutes vous coûte plus qu'une tâche à 8% traitée en 10 minutes**. Lisez les poids de chaque tâche, ils sont affichés.

---

## Ce que j'aurais aimé savoir avant

Brancher mon PC portable avant l’examen : l’outil utilisé pour le passage de la CKA / CKS consomme beaucoup de ressources et donc beaucoup de batterie. J’ai terminé l’épreuve en mode économie d’énergie avec 5 % de batterie

---

## Le cheat sheet : tout en deux pages

Pendant ma préparation, j'ai condensé les commandes essentielles, les structures YAML critiques et les points de vigilance sur chaque domaine dans un cheat sheet de deux pages. C'est ce que j'aurais voulu avoir dès le premier jour.

Je le mets à disposition gratuitement : 
{{< pdf src="/files/cks-cheatsheet.pdf" >}}

Il couvre : SecurityContext, PSS, Falco, NetworkPolicy, Admission Controllers, Istio mTLS, Auditing, RBAC, etcd encryption, CIS Benchmarks, SBOM — avec les commandes et les snippets YAML les plus utiles.

---

## En résumé

La CKS n'est pas un examen de mémorisation. C'est un examen de **compréhension des mécanismes de sécurité Kubernetes et de capacité à travailler sous pression sans casser l'environnement**.

Un mois de préparation est suffisant si vous avez déjà une vraie expérience Kubernetes. La clé : pratiquer les scénarios qui peuvent faire dérailler une session entière (ImagePolicyWebhook en tête), être fluide sur les domaines à fort coefficient, et ne pas perdre de temps sur une tâche bloquante.

Bonne chance pour votre préparation :)
