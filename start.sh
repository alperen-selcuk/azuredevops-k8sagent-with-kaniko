#!/bin/bash
set -e

echo ${AZP_URL}
echo ${AZP_TOKEN}
echo ${AZP_POOL}

# AZP_URL control
if [ -z "${AZP_URL}" ]; then
  echo 1>&2 "error: missing AZP_URL environment variable"
  exit 1
fi

# AZP_TOKEN control
if [ -z "${AZP_TOKEN}" ]; then
  echo 1>&2 "error: missing AZP_TOKEN environment variable"
  exit 1
fi

# AZP_POOL control
if [ -z "${AZP_POOL}" ]; then
  echo 1>&2 "error: missing AZP_POOL environment variable"
  exit 1
fi


if [ -n "${AZP_WORK}" ]; then
  mkdir -p "${AZP_WORK}"
fi

cleanup() {
  trap "" EXIT

  if [ -e ./config.sh ]; then
    print_header "Cleanup. Removing Azure Pipelines agent..."

    # wait agent
    while true; do
      ./config.sh remove --unattended --auth "PAT" --token "${AZP_TOKEN}" && break

      echo "Retrying in 30 seconds..."
      sleep 30
    done
  fi
}

print_header() {
  lightcyan="\033[1;36m"
  nocolor="\033[0m"
  echo -e "\n${lightcyan}$1${nocolor}\n"
}

export VSO_AGENT_IGNORE="AZP_TOKEN,AZP_TOKEN_FILE"

print_header "1. Determining matching Azure Pipelines agent..."

# AZP_TOKEN'ı doğrudan kullan
AZP_AGENT_PACKAGES=$(curl -LsS \
    -u user:"${AZP_TOKEN}" \
    -H "Accept:application/json;" \
    "${AZP_URL}/_apis/distributedtask/packages/agent?platform=${TARGETARCH}&top=1")

AZP_AGENT_PACKAGE_LATEST_URL=$(echo "${AZP_AGENT_PACKAGES}" | jq -r ".value[0].downloadUrl")

if [ -z "${AZP_AGENT_PACKAGE_LATEST_URL}" -o "${AZP_AGENT_PACKAGE_LATEST_URL}" == "null" ]; then
  echo 1>&2 "error: could not determine a matching Azure Pipelines agent"
  echo 1>&2 "check that account "${AZP_URL}" is correct and the token is valid for that account"
  exit 1
fi

print_header "2. Downloading and extracting Azure Pipelines agent..."

curl -LsS "${AZP_AGENT_PACKAGE_LATEST_URL}" | tar -xz & wait $!

source ./env.sh

trap "cleanup; exit 0" EXIT
trap "cleanup; exit 130" INT
trap "cleanup; exit 143" TERM

print_header "3. Configuring Azure Pipelines agent..."

./config.sh --unattended \
  --agent "$(hostname)" \
  --url "${AZP_URL}" \
  --auth "PAT" \
  --token "${AZP_TOKEN}" \
  --pool "${AZP_POOL}" \
  --work "${AZP_WORK}" \
  --replace \
  --acceptTeeEula & wait $!

print_header "4. Running Azure Pipelines agent..."

chmod +x ./run.sh

# azuredevops agent start
./run.sh "$@" & wait $!
