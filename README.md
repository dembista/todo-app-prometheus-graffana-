# MediShop Todo App — TP DevOps

Déploiement complet d'une application de gestion de tâches sur AWS, avec une
chaîne DevOps automatisée de bout en bout : **Terraform** (infrastructure),
**Ansible** (configuration), **Docker** (conteneurisation), **GitHub
Actions** (CI/CD), **Prometheus/Grafana** (supervision) et **SonarCloud**
(qualité de code).

## Sommaire

- [Vue d'ensemble](#vue-densemble)
- [Architecture](#architecture)
- [Stack technique](#stack-technique)
- [Structure du repository](#structure-du-repository)
- [Choix techniques et justifications](#choix-techniques-et-justifications)
- [Reproduire l'infrastructure depuis zéro](#reproduire-linfrastructure-depuis-zéro)
- [Utilisation en local](#utilisation-en-local)
- [Règles de sécurité réseau](#règles-de-sécurité-réseau)
- [Pipeline CI/CD](#pipeline-cicd)
- [Supervision (Prometheus / Grafana)](#supervision-prometheus--grafana)
- [Qualité de code (SonarCloud)](#qualité-de-code-sonarcloud)
- [Dépannage](#dépannage)
- [Gestion des coûts](#gestion-des-coûts)
- [Démonstration pour la soutenance](#démonstration-pour-la-soutenance)

## Vue d'ensemble

MediShop souhaite une Todo App interne, déployée sur AWS de façon reproductible
et automatisée. L'application a 3 endpoints CRUD (création, modification,
suppression, plus une liste), un frontend simple, et tourne entièrement dans
des conteneurs Docker sur 3 instances EC2 séparées (Front / Back / DB). Le
Front héberge également la stack de supervision (Prometheus + Grafana), et le
pipeline CI/CD inclut une analyse de qualité de code (SonarCloud) avant tout
déploiement.

## Architecture

```
                              Internet
                                 |
                                 v
   +---------------------------------------------------------+
   | VPC 10.0.0.0/16                                          |
   |  +------------------------------------------------------+
   |  | Sous-reseau public (10.0.1.0/24)                      |
   |  |  +------------------------+  +------------------+     |
   |  |  |  Front (EC2)            |  |  NAT Gateway      |     |
   |  |  | Nginx + HTTPS            |  | Egress Internet   |     |
   |  |  | reverse proxy            |  | pour le prive      |     |
   |  |  | node_exporter :9100      |  +---------^--------+     |
   |  |  | Prometheus    :9090      |            |               |
   |  |  | Grafana       :3001      |            |               |
   |  |  +--------+-----------------+            |               |
   |  +-----------|-------------------------------|---------------+
   |              |                               |
   |  +-----------|-------------------------------|---------------+
   |  | Sous-reseau prive (10.0.2.0/24)            |               |
   |  |  +--------v----------+      +-----------+------+          |
   |  |  |  Back (EC2)        |----->|  DB (EC2)         |          |
   |  |  | Node/Express :3000 |      | PostgreSQL :5432  |          |
   |  |  +--------------------+      +--------------------+         |
   |  +---------------------------------------------------------+
   +-------------------------------------------------------------+
```

**Flux applicatif :** le navigateur charge la page en HTTPS depuis le Front.
Le JS front appelle `/api/...` en relatif (même origine) — Nginx sur le Front
proxifie ces appels vers le Back sur son IP privée. Le Back parle à la DB sur
son IP privée. Ni le Back ni la DB n'ont d'IP publique ni ne sont joignables
depuis Internet.

**Flux de supervision :** node_exporter (sur le Front) expose les métriques
système de la machine ; Prometheus (sur le Front) les scrape en local ;
Grafana (sur le Front) les affiche dans un dashboard. Tout se passe sur la
même machine (`network_mode: host`), aucun trafic réseau supplémentaire entre
les 3 instances.

**Flux de déploiement (CI/CD) :** un `push` sur `main` déclenche GitHub
Actions, qui lance d'abord une analyse SonarCloud, puis build les images
modifiées, les pousse sur Docker Hub, puis se connecte en SSH (directement au
Front, ou via rebond par le Front pour atteindre le Back) pour déployer le
nouveau conteneur avec rollback automatique en cas d'échec.

## Stack technique

| Composant            | Choix                           | Pourquoi                                              |
| --------------------- | -------------------------------- | ------------------------------------------------------ |
| Frontend              | Vite (JS vanilla)                | Léger, pas de framework superflu pour une todo list    |
| Backend                | Node.js + Express                | Simple, standard, 3 endpoints CRUD                     |
| Base de données        | PostgreSQL (image officielle)    | Prépare la vraie couche DB EC2 du TP                    |
| IaC                    | Terraform                        | Standard de l'industrie, déclaratif, idempotent         |
| Config management       | Ansible                          | Idempotent, agentless (SSH uniquement)                  |
| Conteneurisation        | Docker                           | Chaque appli isolée, portable                           |
| Registre d'images       | Docker Hub                       | Gratuit, simple à intégrer en CI                         |
| CI/CD                  | GitHub Actions                   | Intégré au repo, gratuit pour ce volume                 |
| Reverse proxy / TLS      | Nginx + Certbot (Let's Encrypt)   | Standard, gratuit, renouvellement automatique             |
| Supervision infra        | Prometheus + Grafana + node_exporter | Standard open-source, dashboards communautaires prêts à l'emploi |
| Qualité de code          | SonarCloud                       | SaaS gratuit pour projets publics, zéro serveur à héberger |

## Structure du repository

```
todo-app/
├── frontend/                  # Application Vite (JS vanilla)
│   ├── src/
│   ├── Dockerfile
│   └── .env.example
├── backend/                   # API Express + PostgreSQL
│   ├── src/
│   ├── init.sql               # Création de la table todos
│   ├── Dockerfile
│   └── .env.example
├── terraform/                 # Infrastructure AWS
│   ├── main.tf                # Provider
│   ├── variables.tf           # Toutes les valeurs externalisées
│   ├── vpc.tf                 # VPC, subnets, IGW, NAT Gateway
│   ├── security_groups.tf     # 3 SG stricts par couche
│   ├── ec2.tf                 # 3 instances EC2
│   ├── outputs.tf             # IP front/back/db, SG id
│   └── terraform.tfvars.example
├── ansible/                   # Configuration des serveurs
│   ├── generate_inventory.py  # Génère l'inventaire depuis les outputs Terraform
│   ├── site.yml                # Playbook principal
│   ├── group_vars/
│   │   ├── all.yml             # Variables communes (ports applicatifs)
│   │   └── front/
│   │       ├── main.yml        # domain_name, certbot_email
│   │       └── vault.yml       # grafana_admin_password (chiffré, ansible-vault)
│   └── roles/
│       ├── docker/            # Installe Docker + Compose (3 machines)
│       ├── nginx_front/       # Nginx + reverse proxy + Certbot (Front uniquement)
│       ├── node_exporter/     # Métriques système (Front uniquement)
│       └── monitoring/        # Prometheus + Grafana + alerting (Front uniquement)
│           ├── templates/prometheus.yml.j2
│           └── files/
│               ├── alert.rules.yml            # Règles d'alerte (serveur, conteneurs, CPU, failles, redondances)
│               ├── alertmanager.yml           # Notifications d'alertes (webhook/email)
│               ├── dashboard-todo.json        # Dashboard custom (conteneurs + alertes)
│               ├── grafana-datasource.yml
│               └── grafana-dashboard-provider.yml
├── scripts/
│   └── remote_deploy.sh       # Script de déploiement avec rollback
├── .github/workflows/
│   └── deploy.yml             # Pipeline CI/CD (SonarCloud + build + deploy)
├── sonar-project.properties   # Configuration de l'analyse SonarCloud
└── docker-compose.yml         # Environnement de dev local complet
```

## Choix techniques et justifications

Ces points sont ceux susceptibles d'être posés en soutenance — les réponses
sont préparées à l'avance.

**Pourquoi une NAT Gateway ?**
Back et DB sont dans un sous-réseau privé (aucune IP publique, conforme à la
règle "Internet ne doit jamais atteindre directement le Back ou la DB").
Mais Ansible doit y installer Docker, ce qui nécessite un accès Internet
sortant. La NAT Gateway permet cet accès sortant sans exposer les instances
en entrée. Coût : ~0,045 $/h, à détruire entre les sessions de travail (voir
[Gestion des coûts](#gestion-des-coûts)).

**Pourquoi un rebond SSH (bastion) via le Front ?**
Back et DB n'ayant pas d'IP publique, on ne peut pas s'y connecter
directement depuis l'extérieur. Le Front, seul à avoir une IP publique, sert
de bastion : Ansible et le pipeline CI/CD s'y connectent d'abord, puis
rebondissent (`ProxyJump`) vers Back/DB. Les Security Groups n'autorisent le
SSH vers Back/DB que depuis le Security Group du Front, jamais depuis
Internet.

**Pourquoi whitelister dynamiquement l'IP du runner GitHub dans le SG ?**
Le Security Group du Front n'autorise le SSH que depuis l'IP de
l'administrateur (règle stricte du TP). Mais GitHub Actions utilise des
runners avec des IP différentes à chaque exécution. Plutôt que d'ouvrir le
SSH à tout Internet (ce qui violerait la règle de sécurité), le pipeline
récupère l'IP du runner, l'autorise temporairement via l'API AWS
(`ec2:AuthorizeSecurityGroupIngress`) juste avant le déploiement, puis la
révoque immédiatement après (`if: always()`, donc même en cas d'échec). Le
SSH reste fermé au public en permanence, sauf le temps exact du déploiement.

**Pourquoi un script de rollback dans le déploiement ?**
Avant de remplacer un conteneur, le script sauvegarde le tag de l'image
actuellement en service. Si le nouveau conteneur ne démarre pas (santé
vérifiée après 5s), l'ancien conteneur est automatiquement relancé. Le
premier déploiement (aucun conteneur existant) est aussi géré sans échouer.

**Pourquoi DuckDNS ?**
DuckDNS fournit gratuitement un sous-domaine permettant d'associer un nom DNS
à l'adresse IP publique de l'instance Front. Cela permet d'utiliser un nom de
domaine stable avec Let's Encrypt pour obtenir un certificat HTTPS.
Contrairement à nip.io, l'adresse utilisée est désormais gérée explicitement
dans DuckDNS.

**Pourquoi un monorepo (tout dans un seul dépôt Git) ?**
Le code applicatif, l'infra et la CI/CD sont fortement couplés : le pipeline
a besoin de connaître à la fois le code (pour builder) et l'infra (IP des
instances) pour déployer. Un seul dépôt évite toute désynchronisation entre
ces parties, et correspond à la demande du TP ("Code Terraform versionné sur
un dépôt Git").

**Pourquoi supervise-t-on uniquement le Front, pas Back/DB ?**
Le périmètre demandé pour ce TP est la supervision de l'infrastructure du
Front. Limiter le scope évite d'ouvrir de nouvelles règles réseau entre les
3 machines (chaque ouverture de port supplémentaire est une surface
d'attaque en plus à justifier). Node_exporter, Prometheus et Grafana tournent
tous sur le Front et communiquent en local (`localhost`) — aucun trafic
inter-instances n'est nécessaire. Étendre au Back/DB plus tard ne demanderait
que : le rôle `node_exporter` sur ces hosts, une règle SG ingress 9100 depuis
le SG du Front, et une boucle sur `groups['back']`/`groups['db']` dans le
template Prometheus.

**Pourquoi `network_mode: host` pour Prometheus et Grafana ?**
En mode réseau Docker par défaut (bridge), chaque conteneur a sa propre
interface réseau isolée : quand Prometheus interroge `localhost:9100`, il
cherche dans son propre conteneur, pas sur la machine hôte où tourne
node_exporter — la requête échoue (`connection refused`). Passer ces
conteneurs en `network_mode: host` leur fait partager directement la pile
réseau de la VM, ce qui leur permet de s'atteindre mutuellement via
`localhost`, exactement comme node_exporter le fait déjà. Grafana écoute
alors directement sur le port 3001 en interne, via la variable
`GF_SERVER_HTTP_PORT`, puisque le mapping de port classique (`ports: [...]`)
n'existe plus en mode host.

**Pourquoi Grafana n'est jamais exposé publiquement ?**
Comme le SSH, l'accès au dashboard (port 3001) est restreint à `admin_ip`
uniquement dans le Security Group du Front — jamais `0.0.0.0/0`. Un
dashboard d'administration expose des informations internes (charge système,
utilisation mémoire) qui n'ont pas vocation à être publiques. Pour un accès
depuis plusieurs postes, un tunnel SSH est préférable à l'ouverture du port.

**Pourquoi SonarCloud plutôt que SonarQube auto-hébergé ?**
SonarQube auto-hébergé nécessite un serveur dédié avec au moins 2 Go de RAM
(Elasticsearch interne), ce qui ne rentre pas sur une instance `t3.micro`
déjà occupée par Nginx, l'app et la stack de monitoring — et sortirait du
tier gratuit AWS. SonarCloud est l'équivalent SaaS, gratuit pour les dépôts
publics, sans aucune infrastructure à provisionner ni maintenir.

**Pourquoi désactiver l'"Automatic Analysis" de SonarCloud ?**
Par défaut, SonarCloud propose une analyse automatique côté serveur (à
chaque push, sans passer par le pipeline). Elle entre en conflit avec
l'analyse déclenchée depuis GitHub Actions ("CI-based Analysis") : les deux
ne peuvent pas coexister sur un même projet. On désactive l'automatique
(Administration → Analysis Method) pour que seule l'analyse pilotée par le
pipeline s'exécute — cohérent avec l'objectif du TP de tout centraliser dans
la CI/CD.

## Reproduire l'infrastructure depuis zéro

### Prérequis

- Compte AWS avec l'AWS CLI configuré (`aws configure`)
- Terraform ≥ 1.5
- Ansible + collection `community.docker` (`ansible-galaxy collection install community.docker`)
- Docker (pour les tests locaux)
- Un compte Docker Hub
- Un compte SonarCloud (connecté à GitHub)

### 1. Générer une clé SSH

```bash
ssh-keygen -t ed25519 -f ~/.ssh/medishop-todo -C "medishop-todo"
```

### 2. Provisionner l'infrastructure (Terraform)

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Éditez terraform.tfvars : admin_ip = "VOTRE_IP/32" (curl -4 ifconfig.me)
terraform init
terraform plan
terraform apply
```

Notez les outputs affichés (`front_public_ip`, `back_private_ip`,
`db_private_ip`, `front_security_group_id`).

### 3. Configurer les secrets Ansible (vault)

```bash
cd ../ansible
ansible-vault create group_vars/front/vault.yml
```

Contenu à saisir :

```yaml
grafana_admin_password: <choisis un mot de passe fort>
```

> Astuce : si vim n'est pas confortable, utilisez `EDITOR=nano ansible-vault create ...`.
> Vérifiez toujours le contenu après coup avec
> `ansible-vault view group_vars/front/vault.yml --ask-vault-pass` — un vault
> qui s'affiche vide (aucune ligne) signifie que la sauvegarde a échoué,
> recommencez.

### 4. Configurer les serveurs (Ansible)

```bash
python3 generate_inventory.py   # lit les outputs Terraform automatiquement
ansible-playbook site.yml --ask-vault-pass
```

Installe, dans l'ordre :
- Docker sur les 3 machines
- Nginx + Certbot sur le Front
- node_exporter sur le Front
- Prometheus + Grafana sur le Front

### 5. Démarrer PostgreSQL sur la DB (une seule fois, manuel)

```bash
scp -o "ProxyJump=ubuntu@<FRONT_IP>" -i ~/.ssh/medishop-todo backend/init.sql ubuntu@<DB_IP>:~/init.sql
ssh -J ubuntu@<FRONT_IP> -i ~/.ssh/medishop-todo ubuntu@<DB_IP>

docker run -d --name todo-db --restart unless-stopped -p 5432:5432 \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=<mot_de_passe> \
  -e POSTGRES_DB=todo_app \
  -v pgdata:/var/lib/postgresql/data \
  -v ~/init.sql:/docker-entrypoint-initdb.d/init.sql \
  postgres:16-alpine
```

### 6. Créer le projet SonarCloud

Sur [sonarcloud.io](https://sonarcloud.io), connectez-vous avec GitHub et
importez le dépôt `todo-app`. Notez l'**Organization Key** (visible dans
l'URL `sonarcloud.io/organizations/<clé>/projects`) et le **Project Key**.
Désactivez ensuite l'**Automatic Analysis** dans Administration → Analysis
Method (voir justification ci-dessus).

### 7. Configurer les GitHub Secrets

| Secret                                        | Valeur                                                  |
| ---------------------------------------------- | --------------------------------------------------------- |
| `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN`        | Identifiants Docker Hub (token, pas le mot de passe)      |
| `SSH_PRIVATE_KEY`                              | Contenu de `~/.ssh/medishop-todo` (clé privée)             |
| `FRONT_HOST` / `BACK_HOST` / `DB_HOST`          | IP publique Front, IP privée Back, IP privée DB            |
| `PG_USER` / `PG_PASSWORD` / `PG_DATABASE`       | Identifiants Postgres (mêmes que l'étape 5)                |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`   | Clé IAM dédiée (permissions minimales, voir ci-dessous)    |
| `AWS_REGION`                                   | Ex: `eu-west-3`                                            |
| `FRONT_SG_ID`                                  | `front_security_group_id` (output Terraform)               |
| `SONAR_TOKEN`                                  | Token généré dans SonarCloud (My Account → Security)        |

La clé IAM utilisée par le pipeline n'a besoin que de ces deux permissions,
restreintes au strict nécessaire :

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupIngress"
      ],
      "Resource": "*"
    }
  ]
}
```

### 8. Créer `sonar-project.properties` à la racine du repo

```properties
sonar.organization=<ton-organization-key>
sonar.projectKey=<ton-project-key>
sonar.sources=frontend/src,backend/src
sonar.exclusions=**/node_modules/**,**/dist/**
```

### 9. Déclencher le premier déploiement

```bash
git push origin main
```

Le pipeline lance d'abord l'analyse SonarCloud, puis build et déploie
automatiquement ce qui a changé (`frontend/` et/ou `backend/`).

## Utilisation en local

Pour développer/tester sans toucher à AWS :

```bash
docker compose up --build
```

- Frontend : http://localhost:8080
- Backend : http://localhost:3000/api/todos
- Postgres : localhost:5433 (mappé sur le port interne 5432, pour éviter un
  conflit avec un Postgres déjà installé en local)

Les healthchecks garantissent l'ordre de démarrage (`db` → `backend` →
`frontend`), pas besoin de relancer la commande en cas de démarrage à froid.

## Règles de sécurité réseau

| Règle                                          | Implémentation                                          |
| ------------------------------------------------ | ----------------------------------------------------------- |
| Internet → Front uniquement                       | SG Front : ingress 80/443 depuis `0.0.0.0/0`                |
| Admin SSH → Front uniquement, depuis son IP        | SG Front : ingress 22 depuis `admin_ip/32`                  |
| Admin Grafana → Front uniquement, depuis son IP     | SG Front : ingress 3001 depuis `admin_ip/32`                 |
| Front → Back                                      | SG Back : ingress 3000 depuis le SG Front                    |
| Back → DB                                         | SG DB : ingress 5432 depuis le SG Back                        |
| Aucune autre communication                         | Pas d'autre règle d'ingress sur aucun SG                       |
| SSH Front → Back/DB (bastion, pour Ansible/CI)      | SG Back/DB : ingress 22 depuis le SG Front uniquement          |
| Prometheus → node_exporter, Grafana → Prometheus     | Aucune règle réseau : communication en local (`localhost`), tout tourne sur le Front |

## Pipeline CI/CD

Déclenché sur chaque `push` vers `main` :

1. **`changes`** — détecte si `frontend/` et/ou `backend/` ont changé
   (`dorny/paths-filter`)
2. **`sonarcloud`** — analyse statique du code (bugs, vulnérabilités, code
   smells) via SonarCloud ; les jobs de build en dépendent (`needs:`)
3. **`build-frontend` / `build-backend`** — build l'image Docker concernée
   uniquement, push sur Docker Hub avec deux tags (`latest` et le SHA du
   commit)
4. **`deploy-frontend` / `deploy-backend`** — whitelist temporaire de l'IP du
   runner sur le SG Front → connexion SSH (directe pour le Front, via
   `ProxyJump` pour le Back) → exécution de `remote_deploy.sh` (pull, arrêt
   de l'ancien conteneur, lancement du nouveau, vérification de santé,
   rollback automatique si échec) → révocation de la whitelist SSH

## Supervision (Prometheus / Grafana)

Stack de monitoring installée sur le Front : infrastructure de la machine
(CPU, RAM, disque, réseau, uptime), état et santé des conteneurs Docker, et
**alerting** sur tout ça (état serveur, CPU, conteneurs, failles, redondances).

**Composants (tous sur le Front, `network_mode: host`) :**
- `node_exporter` (port 9100) — expose les métriques système
- `cadvisor` (port 9101) — expose les métriques des conteneurs Docker
  (CPU, mémoire, restarts, dernière activité)
- `prometheus` (port 9090, non exposé à Internet) — scrape node_exporter et
  cAdvisor en local, évalue les règles d'alerte
- `alertmanager` (port 9093, non exposé à Internet) — reçoit les alertes et
  les achemine vers les canaux de notification (webhook/email, à configurer)
- `grafana` (port 3001) — affiche les dashboards

**Alertes (`alert.rules.yml`) :**

Le fichier `ansible/roles/monitoring/files/alert.rules.yml` définit toutes les
règles d'alerte, regroupées par thème :

| Groupe | Ce qu'il surveille | Exemples de règles |
| ------ | ------------------ | ------------------ |
| `etat-serveur.rules` | La machine | ServeurInjoignable, CpuServeurEleve (>85%), MemoireServeurElevee (>90%), DisquePresquePlein (<15%), DisqueVaSeRemplir, ChargeServeurElevee, ServeurRedemarre, HorlogeServeurDecalee |
| `etat-conteneurs.rules` | Les conteneurs Docker | ConteneurInjoignable (>60s sans signal), BoucleDeRedemarrageConteneur (>3 restarts/15 min), CpuConteneurEleve (>80%), MemoireConteneurElevee (>512 Mo) |
| `failles-redondances.rules` | Pannes et redondance | CibleDeScrapeHorsLigne, RedondancePerdue (job entier disparu), RedondancePartielle, PointDeDefaillanceUnique |
| `prometheus.rules` | La supervision elle-même | PrometheusRedemarrageFrequent, PrometheusStockageRisque |

Chaque alerte porte un label `severity` (`critical`/`warning`/`info`) et un
type (`serveur`/`conteneur`/`faille`/`redondance`/`supervision`), ce qui
permet de filtrer facilement dans Prometheus et Grafana.

**Dashboards Grafana (provisionnés automatiquement) :**
- "Node Exporter Full" — métriques système de la machine (dashboard 1860)
- "MediShop Todo — Supervision complète" (`dashboard-todo.json`) — vue
  conteneurs (CPU, mémoire, restarts, dernière activité), état des cibles
  (`up`), charge serveur, et **liste des alertes déclenchées**

**Voir les alertes en temps réel :**
- Dans Prometheus : `http://<FRONT_IP>:9090/alerts` (via tunnel SSH,
  `ssh -L 9090:localhost:9090 ubuntu@<FRONT_IP>`)
- Dans Grafana : le panneau "Alertes déclenchées" du dashboard, ou l'onglet
  "Alerting" de l'interface Grafana
- Dans Alertmanager : `ssh -L 9093:localhost:9093` puis tapes
  `http://localhost:9093`

**Accès Grafana :**

```
http://<FRONT_PUBLIC_IP>:3001
```

Réservé à `admin_ip` (même règle que le SSH). Identifiants : `admin` / le
mot de passe défini dans `group_vars/front/vault.yml`.

Les dashboards sont provisionnés automatiquement au premier déploiement
d'Ansible — aucune configuration manuelle nécessaire dans l'interface Grafana.

## Qualité de code (SonarCloud)

Le job `sonarcloud` du pipeline analyse `frontend/src` et `backend/src` à
chaque push, avant tout build ou déploiement. Le rapport est visible sur le
dashboard du projet sur [sonarcloud.io](https://sonarcloud.io).

> Les `package.json` frontend/backend n'ont pas de script `test` : l'analyse
> couvre donc bugs, vulnérabilités et code smells (analyse statique), mais
> sans rapport de couverture de tests. Pour l'ajouter plus tard : générer un
> rapport LCOV (`vitest`, `jest`...) et déclarer
> `sonar.javascript.lcov.reportPaths` dans `sonar-project.properties`.

Un Quality Gate bloquant (qui empêcherait le déploiement en cas d'échec de
l'analyse) peut être ajouté avec l'étape
`SonarSource/sonarqube-quality-gate-action@v1` dans le job `sonarcloud`.

## Dépannage

**`Failed to fetch` côté frontend** — vérifier que `VITE_API_URL` est bien
géré comme "vide = chemin relatif" côté build (`!== undefined`, pas `||`,
qui traite `""` comme falsy en JS).

**`502 Bad Gateway`** — le backend n'est probablement pas déployé ou est
arrêté. Vérifier avec `docker ps -a` sur l'instance Back (via le bastion
Front).

**Erreur CORS** — vérifier que `CORS_ORIGIN` côté backend inclut bien
l'origine réellement utilisée par le navigateur.

**`ssh-keyscan`/SSH échoue depuis GitHub Actions** — vérifier que les 4
secrets AWS (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`,
`FRONT_SG_ID`) sont bien configurés : c'est la whitelist dynamique qui
autorise le runner.

**Port déjà utilisé en local (`5432` par ex.)** — un Postgres local tourne
probablement déjà sur la machine ; le `docker-compose.yml` utilise `5433`
côté hôte pour éviter ce conflit.

**Dashboard Grafana affiche "No data" partout / filtres Job-Host vides** —
symptôme d'un conteneur Prometheus ou Grafana resté en réseau bridge
(`ports: [...]`) au lieu de `network_mode: host`. Vérifier
`http://<FRONT_IP>:9090/targets` (via tunnel SSH,
`ssh -L 9090:localhost:9090 ubuntu@<FRONT_IP>`) : si `node_exporter` est
`DOWN` avec une erreur `connection refused`, Prometheus n'est pas en mode
host. Si les targets sont `UP` mais Grafana reste vide, tester une requête
`up` dans Grafana → Explore : si elle échoue avec le même type d'erreur,
c'est Grafana qui n'est pas en mode host.

**`ansible-vault view` n'affiche rien** — le fichier vault a été sauvegardé
vide (souvent en tapant du texte dans vim avant d'être passé en mode
insertion avec `i`). Supprimer le fichier et le recréer, idéalement avec
`EDITOR=nano ansible-vault create ...` pour éviter les pièges de vim.

**Ansible ignore les variables de `group_vars/front/`** — vérifier qu'il n'y
a pas à la fois un fichier `group_vars/front.yml` et un dossier
`group_vars/front/` : les deux ne peuvent pas coexister proprement. Tout
regrouper dans le dossier (`group_vars/front/main.yml`,
`group_vars/front/vault.yml`).

**SonarCloud : `Organization key '...' does not exist`** — la clé
d'organisation dans `sonar-project.properties` ne correspond pas à la clé
réelle. La retrouver dans l'URL `sonarcloud.io/organizations/<clé>/projects`.

**SonarCloud : `You are running CI analysis while Automatic Analysis is
enabled`** — désactiver l'Automatic Analysis dans Administration → Analysis
Method sur le projet SonarCloud (voir [Choix techniques](#choix-techniques-et-justifications)).

## Gestion des coûts

Seule la **NAT Gateway** engendre un coût garanti (~0,045 $/h + trafic). Les
instances EC2 `t3.micro` restent gratuites tant que le compte est éligible
au tier gratuit AWS. Prometheus, Grafana et SonarCloud n'ajoutent aucun coût
supplémentaire (conteneurs sur une instance déjà existante, et SaaS gratuit).

Entre deux sessions de travail :

```bash
cd terraform
terraform destroy
```

Pour tout recréer à l'identique :

```bash
terraform apply
cd ../ansible && python3 generate_inventory.py && ansible-playbook site.yml --ask-vault-pass
# + redémarrer le conteneur Postgres sur la DB (étape 5 ci-dessus)
```

## Démonstration pour la soutenance

1. Montrer l'application fonctionnelle en HTTPS (`https://<domaine>`)
2. Montrer le dashboard Grafana (`http://<FRONT_IP>:3001`) avec les
   métriques CPU/RAM/disque en temps réel du Front
3. Montrer le dashboard SonarCloud du projet (bugs, vulnérabilités, code
   smells détectés)
4. Modifier un détail visible du frontend, `git push`
5. Suivre le pipeline en direct sur l'onglet GitHub Actions : `sonarcloud` →
   `build-frontend` → `deploy-frontend`
6. Rafraîchir le site : le changement est visible sans aucune action manuelle
7. (Optionnel) Montrer le rollback : déployer une image volontairement
   cassée et observer le script relancer automatiquement l'ancienne version