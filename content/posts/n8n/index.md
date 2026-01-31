---
title: "Veille technologique intelligente : 0€ par mois grâce à n8n et Mistral AI"
date: 2026-01-31
summary: "Une veille technologique 100% automatisée avec n8n et Mistral AI, le tout sans frais mensuels"
tags: ["kubernetes", "n8n", "self-hosting", "web", "veille", "ia", "automatisation"]
categories: ["middleware"]
featuredImage: "featured.png"
---

## 🚨 Le parcours du combatant

Après **5 ans de galère**, je pense que j'ai enfin trouvé une solution que je vais garder quelques années pour faire ma veille techno.

J'ai pu tester de nombreuses solutions, mais la plupart ne m'aidaient pas vraiment à faire ma veille, et me **saturaient d'informations** dont la majorité du temps je n'en avais pas besoin.

J'ai essayé :
- 📰 Des **agrégateurs de flux RSS en ligne** (Feedly, Inoreader...)
- 🏠 Des solutions **self-hosted** comme [Glance](https://github.com/glanceapp/glance)
- 📚 Des lecteurs RSS classiques

Mais au final, je n'étais **jamais satisfait** du résultat. Le problème principal ? **L'infobésité**.


---

## 💡 Pourquoi n8n + Mistral AI ?

J'utilisais déjà **n8n** pour automatiser quelques tâches simples. De plus en plus, en faisant les mises à jour de n8n, j'ai vu une forte intégration des **agents IA**.

Je me suis donc dit il y a maintenant environ **6 mois** : pourquoi pas essayer de faire ma veille techno avec ça ?

### Le problème à résoudre

Le truc, c'est que je ne voulais pas que mon agent IA puisse accéder à ce qu'il voulait sur internet, car il allait me ressortir **tout et n'importe quoi**.

### Ma solution

✅ Lui fournir **moi-même** les articles que je voulais qu'il analyse  
✅ Lui demander de me choisir les **plus pertinents** selon différents critères que je lui aurais donnés  
✅ Éviter les **hallucinations** en ne travaillant qu'avec des sources réelles  

---

## 🏗️ Architecture du workflow

Voici le workflow que j'ai mis en place :

{{< mermaid >}}

graph LR
    A[📡 Flux RSS] --> B[📅 Tri par date]
    B --> C[📝 Rédaction des flux]
    C --> D[🤖 Agent IA Mistral]
    D --> E[✨ Formatage JSON]
    E --> F[💬 Discord]
    
    style A fill:#3b82f6,stroke:#1e40af,stroke-width:2px,color:#fff
    style D fill:#8b5cf6,stroke:#6d28d9,stroke-width:2px,color:#fff
    style F fill:#10b981,stroke:#059669,stroke-width:2px,color:#fff
{{< /mermaid >}}

---

## 🎥 Le workflow en action

Vous voulez voir comment tout ça fonctionne concrètement ?

{{< video src="workflow-n8n.mp4" >}}


**Le processus en détail :**

1. 📡 **Collecte** : Récupération automatique des flux RSS
2. 📅 **Filtrage temporel** : Articles des dernières 9 heures uniquement
3. 📝 **Agrégation** : Consolidation de tous les articles
4. 🤖 **Analyse IA** : Mistral AI sélectionne les plus pertinents
5. ✨ **Formatage** : Structuration en JSON propre
6. 💬 **Notification** : Envoi sur Discord

---

## ⚙️ Mes choix techniques

Maintenant que j'avais décidé du fonctionnement de l'orchestration, j'ai dû choisir : **les URLs RSS**, **le LLM**, et **la réception des articles**.

### 📰 Sources RSS sélectionnées

Pour la veille DevOps/SRE, j'ai choisi :

- 🔐 [The Hacker's News](https://feeds.feedburner.com/TheHackersNews)
- 🇫🇷 [CERT-FR](https://www.cert.ssi.gouv.fr/feed/)
- 🔧 [r/devops](https://www.reddit.com/r/devops/.rss)
- 🛠️ [r/sre](https://www.reddit.com/r/sre/.rss)
- ☸️ [r/kubernetes](https://www.reddit.com/r/kubernetes/.rss)

### 🧠 Le LLM : Mistral AI

J'ai choisi d'aller chez **Mistral AI** (`mistral-large-2512`) car :

- 🇫🇷 **Français** et souverain
- 🆓 **1M tokens/mois gratuits** (largement suffisant)
- ⚡ **Rapide** et performant
- 🎯 **Excellent** pour l'analyse de texte

### 💾 Cache Redis

Pour être sûr qu'il ne me ressorte pas d'articles qu'il m'a déjà présentés, j'utilise un **cache Redis** pour augmenter son context window à **10 jours**.

Cela permet :
- ✅ Pas de doublons
- ✅ Mémoire des articles déjà traités
- ✅ Cohérence dans le temps

### 💬 Notification Discord

Pour la réception d'articles, c'est simple : je vais envoyer tout ça sur **Discord** dans un channel privé.

Pourquoi Discord ?
- 📱 Accessible mobile/desktop
- 🔔 Notifications push
- 🎨 Formatage markdown
- 🔗 Liens cliquables

---

## 🎯 Mon prompt système

Voici le **prompt système** que j'utilise pour guider mon agent IA :

```text
You are a DevOps / SRE curation agent.
Respond in FRENCH only.

IMPORTANT OUTPUT RULES (ABSOLUTE):
- Return a RAW JSON OBJECT only
- NOT an array
- NOT wrapped in "name", "arguments", or "output"
- DO NOT use function calling
- NO text before or after the JSON

MISSION:
From multiple RSS articles, select ONLY high-signal DevOps / SRE content.
Additionally, suggest ONE new DevOps/SRE tool or project that would be 
interesting to explore in a POC (proof-of-concept).
...
```

---

## ✨ Les avantages de cette approche

| Avantage | Description |
|----------|-------------|
| 💰 **100% gratuit** | Dans les limites de l'API Mistral (1M tokens/mois) |
| ⏱️ **Gain de temps massif** | 5 min/jour au lieu d'1h de scroll RSS |
| 🎯 **Pertinence** | Plus de noyade dans les flux RSS |
| 🔧 **Personnalisable** | Adaptable à N'IMPORTE QUEL domaine |
| 🏠 **Self-hosted** | Contrôle total de ses données |
| 📈 **Évolutif** | Facile d'ajouter de nouvelles sources |
| 🚫 **Zéro hallucination** | L'IA travaille uniquement sur des sources réelles |

---

## 🚀 Améliorations futures

Il me reste encore quelques ajustements que j'aimerais bien faire :

### 🗄️ Base de données vectorielle

- Déployer **Qdrant** ou **Weaviate**
- Faire un **préfiltrage sémantique** des articles
- Améliorer le **context window** de mon agent IA
- Recherche par **similarité** dans l'historique

### 🎓 Apprentissage des préférences

J'aimerais également mettre en place un système de **feedback** :
- Indiquer si un article est intéressant ou pas
- L'agent IA commence à **apprendre mes préférences**
- Affinage progressif des critères de sélection

---

## 🌍 Au-delà de la techno

Cette veille peut être adaptée à **n'importe quel domaine** :

- 💼 **Finance** : marchés, crypto, réglementation
- 📊 **Marketing** : tendances, outils, growth hacking
- 👥 **RH** : recrutement, management, bien-être
- ⚖️ **Juridique** : lois, jurisprudence, RGPD
- 🏥 **Santé** : recherche médicale, innovations
- 🎨 **Design** : UI/UX, tendances, outils

Il suffit d'adapter :
- 📝 Le **prompt système**
- 📡 Les **sources RSS**
- 🎯 Les **critères de sélection**

---

## 💼 Besoin d'aide pour déployer votre veille ?

En tant que **freelance DevOps/SRE** (soirs et weekends), je propose :

✅ **Déploiement** de n8n sur votre infra (ou cloud)  
✅ **Configuration** du workflow de veille sur-mesure  
✅ **Adaptation** à votre domaine métier  
✅ **Formation** à l'utilisation et personnalisation  

📧 **Contact** : florianspk@gmail.com
💼 **LinkedIn** : https://www.linkedin.com/in/florian-spick/
⏰ **Disponibilité** : soirs et weekends  

---

## 🎬 Conclusion

Après **5 ans de recherche**, j'ai enfin une veille techno qui me fait **gagner du temps** au lieu d'en perdre
Le meilleur ? Cette solution est **réplicable par n'importe qui** avec un minimum de connaissances techniques

---

{{< alert >}}
**Astuce** : Ce workflow tourne chez moi depuis 6 mois sans interruption. Le coût total ? **0€** grâce aux offres gratuites de Mistral AI et au self-hosting de n8n.
{{< /alert >}}
