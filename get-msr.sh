#!/bin/bash
# https://docs.mirantis.com/msr/3.0/install/install-offline/prepare-your-environment.html

set -e

POSTGRES_OPERATOR_VERSION=1.7.1
CERT_MANAGER_VERSION=1.7.2
MSR_CHART_VERSION=1.0.6
QUIET_MODE=0

declare -a IMAGES=()

pull_images_for() {
    echo "Pulling images for '$1'..."

    pushd "$1" > /dev/null || exit

    helm template . \
    | yq e "..|.image? | select(.)" - \
    | grep -wv "\-\-\-" | sort -u | xargs -L1 docker pull
    
    popd > /dev/null || exit
}

backup_images() {
    images=$(docker images "$1" --format "table {{.Repository}}:{{.Tag}}" | tail -n +2)

    for image in $images ; do
        echo "Processing $image"
        IMAGES+=("$image")
    done
}

help() {
   echo ""
   echo "Usage: $0 --postgres version --certmanager version --msr version --msrchart version"
   echo -e "\t--postgres - postgres-operator chart version"
   echo -e "\t--certmanager - cert-manager chart version"
   echo -e "\t--msrchart - MSR Chart Version"
   exit 1 # Exit script after printing help
}

prompt() {
  echo ""
  echo "Welcome to MSR packaging utility."
  echo ""
  echo "This will download and package all the required helm charts and images"
  echo "for offline MSR installation in an air-gapped environment."
  echo ""
  echo "Current options:"
  echo ""
  echo "Postgres Operator Version=${POSTGRES_OPERATOR_VERSION}"
  echo "Cert Manager Version=${CERT_MANAGER_VERSION}"
  echo "MSR Chart Version=${MSR_CHART_VERSION}"
  echo ""
  echo "1) Proceed with packaging MSR"
  echo "2) Customize parameters"
  echo "3) Cancel"
  echo ""
}

ask() {
  echo "I'm going to ask you the value of each of these options."
  echo "You may simply press the Enter key to leave unchanged."
  echo ""
  read -rp "Postgres Operator Version? [${POSTGRES_OPERATOR_VERSION}] " input
  POSTGRES_OPERATOR_VERSION=${input:-$POSTGRES_OPERATOR_VERSION}
  echo ""
  read -rp "Cert Manager Version? [${CERT_MANAGER_VERSION}] " input
  CERT_MANAGER_VERSION=${input:-$CERT_MANAGER_VERSION}
  echo ""
  read -rp "MSR Chart Version? [${MSR_CHART_VERSION}] " input
  MSR_CHART_VERSION=${input:-$MSR_CHART_VERSION}
  echo ""
}

while [ $# -gt 0 ]; do
  case "$1" in
    -postgres|--postgres)
      POSTGRES_OPERATOR_VERSION="$2"
      QUIET_MODE=1
      ;;
    -certmanager|--certmanager)
      CERT_MANAGER_VERSION="$2"
      QUIET_MODE=1
      ;;
    -msrchart|--msrchart)
      MSR_CHART_VERSION="$2"
      QUIET_MODE=1
      ;;
    -help|--help)
      help
      ;;
    *)
      echo "***************************"
      echo "* Error: Invalid argument *"
      echo "***************************"
      help
  esac
  shift
  shift
done

# if not a quite mode - display prompt
# quite mode should just run all default settings
if [ $QUIET_MODE -eq 0 ]
then
  prompt
  read -rp "Select an option: " answer
  while : ; do
    case "$answer" in
      1)
        break
        ;;
      2)
        ask
        prompt
        read -rp "Select an option: " answer
        ;;
      3)
        exit 1
        ;;
      *)
        prompt
        read -rp "Select an option: " answer
        ;;
    esac
  done
fi

echo "Packaging..."
echo ""

echo "Configure helm repository..."
helm repo add postgres-operator https://opensource.zalando.com/postgres-operator/charts/postgres-operator/
helm repo add jetstack https://charts.jetstack.io
helm repo add msrofficial https://registry.mirantis.com/charts/msr/msr

echo "Update helm repository..."
helm repo update

echo "Pulling charts..."
helm pull postgres-operator/postgres-operator --version "$POSTGRES_OPERATOR_VERSION"
helm pull jetstack/cert-manager --version "$CERT_MANAGER_VERSION"
helm pull msrofficial/msr --version "$MSR_CHART_VERSION"

MSR_VERSION=$(helm search repo msrofficial/msr -o yaml | yq e "..|.app_version? | select(.)" -)

echo "Preparing charts..."
tar zxvf "cert-manager-v${CERT_MANAGER_VERSION}.tgz"
tar zxvf "postgres-operator-${POSTGRES_OPERATOR_VERSION}.tgz"
tar zxvf "msr-${MSR_CHART_VERSION}.tgz"

pull_images_for postgres-operator
pull_images_for cert-manager

echo "Pulling images for 'msr'..."
pushd msr > /dev/null || exit
helm template . --api-versions=acid.zalan.do/v1 --api-versions=cert-manager.io/v1 \
| yq e "..|.image? | select(.)" - \
| grep -wv "\-\-\-" | sort -u | xargs -L1 docker pull
popd > /dev/null || exit

echo "Extracting images..."
backup_images "registry.mirantis.com/msr/*${MSR_VERSION}"
backup_images "registry.mirantis.com/msr/enzi*${MSR_CHART_VERSION}"
backup_images "mirantis/rethinkdb"
backup_images "quay.io/jetstack/cert-manager-*v${CERT_MANAGER_VERSION}"
backup_images "registry.opensource.zalan.do/acid/postgres-operator*v${POSTGRES_OPERATOR_VERSION}"

OUTPUT_FILE="msr-${MSR_VERSION}.tar"

docker save "${IMAGES[@]}" -o "$OUTPUT_FILE"

echo "Removing temp directories and files..."
rm -rf postgres-operator
rm -rf cert-manager
rm -rf msr

echo "Done. Use 'docker load < ${OUTPUT_FILE}' to load these images elsewhere."
