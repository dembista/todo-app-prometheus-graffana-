#!/usr/bin/env bash
# Script de déploiement générique, exécuté À DISTANCE sur l'instance cible.
# Gère deux cas requis par le TP (section 3.4) :
#   - premier déploiement (aucun conteneur existant) : ne doit pas échouer
#   - rollback : si le nouveau conteneur ne démarre pas, on relance l'ancien
#
# Usage :
#   remote_deploy.sh <container_name> <image> <host_port> <container_port> [-e KEY=VALUE ...]

set -euo pipefail

CONTAINER_NAME="$1"
IMAGE="$2"
HOST_PORT="$3"
CONTAINER_PORT="$4"
shift 4
EXTRA_ENV_ARGS=("$@") # ex: -e PORT=3000 -e PGHOST=10.0.2.40 ...

STATE_DIR="$HOME/.deploy"
STATE_FILE="$STATE_DIR/${CONTAINER_NAME}_previous_image"
mkdir -p "$STATE_DIR"

echo "==> Pull de la nouvelle image : $IMAGE"
docker pull "$IMAGE"

# Sauvegarder l'image actuellement en service, pour rollback éventuel.
if docker inspect "$CONTAINER_NAME" > /dev/null 2>&1; then
  PREVIOUS_IMAGE="$(docker inspect --format='{{.Config.Image}}' "$CONTAINER_NAME")"
  echo "$PREVIOUS_IMAGE" > "$STATE_FILE"
  echo "==> Image precedente sauvegardee pour rollback : $PREVIOUS_IMAGE"
else
  echo "==> Aucun conteneur existant (premier deploiement), pas de rollback possible pour cette fois"
fi

echo "==> Arret et suppression de l'ancien conteneur (si present)"
docker stop "$CONTAINER_NAME" > /dev/null 2>&1 || true
docker rm "$CONTAINER_NAME" > /dev/null 2>&1 || true

start_container() {
  local image_to_run="$1"
  docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    -p "${HOST_PORT}:${CONTAINER_PORT}" \
    "${EXTRA_ENV_ARGS[@]}" \
    "$image_to_run"
}

echo "==> Lancement du nouveau conteneur"
start_container "$IMAGE"

echo "==> Verification du demarrage (5s)"
sleep 5

if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || echo false)" != "true" ]; then
  echo "==> ECHEC : le nouveau conteneur ne tourne pas. Logs :"
  docker logs "$CONTAINER_NAME" || true
  docker rm -f "$CONTAINER_NAME" > /dev/null 2>&1 || true

  if [ -f "$STATE_FILE" ]; then
    PREVIOUS_IMAGE="$(cat "$STATE_FILE")"
    echo "==> ROLLBACK : redemarrage de l'image precedente ($PREVIOUS_IMAGE)"
    start_container "$PREVIOUS_IMAGE"
    echo "==> Rollback effectue, mais le deploiement a echoue"
    exit 1
  else
    echo "==> Aucune image precedente disponible : rollback impossible"
    exit 1
  fi
fi

echo "==> Deploiement reussi : $CONTAINER_NAME tourne avec $IMAGE"