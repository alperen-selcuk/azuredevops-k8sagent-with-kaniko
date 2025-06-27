#!/bin/bash

read -p "AZUREDEVOPS_URL : " URL
read -p "AZUREDEVOPS_PAT : " PAT
read -p "AZUREDEVOPS_POOL : " POOL
read -p "KUBERNETES NAMESPACE :" NS

kubectl create secret generic azdevops \
  --from-literal=AZP_URL=$URL \
  --from-literal=AZP_TOKEN=$PAT \
  --from-literal=AZP_POOL=$POOL \
  -n $NS
