---
title: "Comment j'ai accéléré mes backups perso avec Garage (S3) et Restic"
date: 2026-02-09
draft: false
tags: ["backup", "self-hosted", "s3", "garage", "restic", "nas"]
categories: ["Infrastructure", "Tutoriel"]
description: "Pourquoi et comment je suis passé de backups SFTP lents à une solution S3 souveraine avec GarageFS et Restic"
---

## Mon problème de backup actuel

- Mon setup initial : NAS Asustor de récup + Déjà Dup + SFTP
- Le constat : backups **extrêmement lents** (> 1h pour 100 Go), et souvent interrompus

## Pourquoi j'ai choisi Garage plutôt que MinIO

- Besoin d'une solution S3 compatible pour Restic
- Les déboires de MinIO (politiques de licence, direction du projet)
- **Garage : solution française, open-source, souveraine** 🇫🇷
- Léger, adapté au self-hosting, communauté active

## Déploiement de Garage : ridiculement simple

### Prérequis

- Docker + Docker Compose
- Un NAS ou serveur Linux

### Installation en 3 commandes

{{< github repo="florianspk/garageFS" showThumbnail=true >}}

**1. Cloner la configuration**
```bash
git clone git@github.com:florianspk/garageFS.git
cd garageFS
```

**2. Configurer le secret RPC**
```bash
echo "RPC_SECRET=$(openssl rand -base64 32)" > .env
```

**3. Démarrer Garage**
```bash
docker compose up -d
```

### Initialisation du cluster
```bash
# Les 4 commandes essentielles
NODE_ID=$(docker exec garage ./garage node id | head -n1 | cut -d'@' -f1)
docker exec garage ./garage layout assign -z dc1 -c 100G $NODE_ID
docker exec garage ./garage layout show
docker exec garage ./garage layout apply --version 1
```

**L'interface UI est accessible sur** `http://localhost:3909/`

## Création des credentials + bucket S3

{{< video
    src="garage.mp4"
    loop=true
    muted=true
>}}

## Restic : des backups enfin rapides

### Installation de Restic
```bash
# Linux / macOS
brew install restic
```

### Configuration du backend S3
```bash
# Variables d'environnement
export AWS_ACCESS_KEY_ID="votre-access-key" # Key ID 
export AWS_SECRET_ACCESS_KEY="votre-secret-key" # Secret Key
export RESTIC_REPOSITORY="s3:http://localhost:3900/restic-backup"
export RESTIC_PASSWORD="password-secure" # Mot de passe pour Restic

# Initialiser le repository
restic init
```

### Premier backup
```bash
restic backup /home/user/Documents /home/user/Photos
```

**Résultat : ~10x plus rapide** qu'avec Déjà Dup/SFTP ! 🚀

### Automatisation avec systemd/cron
```bash
# /etc/cron.daily/restic-backup
#!/bin/bash
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export RESTIC_REPOSITORY="s3:http://localhost:3900/restic-backup"
export RESTIC_PASSWORD="..."

restic backup /home/user/Documents /home/user/Photos --tag daily
restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
```

## Prochaines étapes : Kubernetes et bases de données

Cette stack Garage + Restic ne s'arrête pas au backup de mon PC. Je prévois de l'utiliser pour :

- **Backup de mes bases de données** (PostgreSQL, MySQL)
- **Backup des PVC Kubernetes** (volumes persistants)
- **Backup applicatif** pour mes projets clients

## Besoin d'une solution similaire pour votre entreprise ?

**Je suis freelance Infrastructure/DevOps** disponible soirs et week-ends pour vous accompagner sur :

✅ Mise en place de solutions de backup robustes et performantes  
✅ Migration vers des infrastructures souveraines et open-source  
✅ Architecture S3 self-hosted (Garage, alternatives à MinIO)  
✅ Automatisation de backups Kubernetes (Velero, Restic)  

📧 Contact : florianspk@gmail.com

## Conclusion

Le passage de SFTP vers S3 (Garage) + Restic a transformé ma stratégie de backup :

- **Rapidité** : ~10x plus rapide
- **Fiabilité** : déduplication, chiffrement, vérification d'intégrité
- **Souveraineté** : données en France, solution open-source
- **Évolutivité** : prêt pour Kubernetes et workloads professionnels

Le tout déployé en moins de 30 minutes. **Vive le self-hosting intelligent !** 🇫🇷
```
