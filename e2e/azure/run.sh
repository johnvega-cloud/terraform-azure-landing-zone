#!/usr/bin/env bash
# End-to-end test in a real Azure subscription.
# apply (dev values, own prefix and workspace) -> checks with az -> policy probes
# -> second plan must be empty -> destroy (always, even if a check fails).
#
# Usage (from the repo root):  az login && e2e/azure/run.sh
# Creates only free resources (RG, VNet, NSGs, policy assignments).
set -euo pipefail

cd "$(dirname "$0")/../.."

PREFIX="${E2E_PREFIX:-azlze2e}"
ENV="dev"
RG="${PREFIX}-${ENV}-rg"
WS="e2e"
VARS=(-var-file="envs/${ENV}.tfvars" -var="prefix=${PREFIX}")

export ARM_SUBSCRIPTION_ID="${ARM_SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"

pass=0
fail=0
check() { # check "<description>" "<expected>" "<actual>"
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"; pass=$((pass + 1))
  else
    echo "FAIL  $1 (expected '$2', got '$3')"; fail=$((fail + 1))
  fi
}

cleanup() {
  echo "--- destroy"
  az network nsg delete -g "$RG" -n probe-ok >/dev/null 2>&1 || true
  terraform destroy "${VARS[@]}" -auto-approve -input=false -no-color >/dev/null
  check "resource group removed" "false" "$(az group exists -n "$RG")"
  terraform workspace select default >/dev/null
  terraform workspace delete "$WS" >/dev/null
  echo "--- ${pass} passed, ${fail} failed"
  [[ "$fail" -eq 0 ]]
}

if [[ "$(az group exists -n "$RG")" == "true" ]]; then
  echo "Resource group $RG already exists; refusing to run." >&2
  exit 1
fi

terraform init -input=false >/dev/null
terraform workspace select -or-create "$WS" >/dev/null
trap cleanup EXIT

echo "--- apply"
terraform apply "${VARS[@]}" -auto-approve -input=false -no-color >/dev/null

echo "--- resources"
check "resource group exists" "true" "$(az group exists -n "$RG")"
check "vnet address space" "10.10.0.0/16" \
  "$(az network vnet show -g "$RG" -n "${PREFIX}-${ENV}-vnet" --query 'addressSpace.addressPrefixes[0]' -o tsv)"
for s in app:10.10.1.0/24 data:10.10.2.0/24; do
  name="${s%%:*}"; cidr="${s#*:}"
  check "$name subnet prefix" "$cidr" \
    "$(az network vnet subnet show -g "$RG" --vnet-name "${PREFIX}-${ENV}-vnet" -n "${PREFIX}-${ENV}-${name}-snet" --query addressPrefix -o tsv)"
  check "$name subnet has its NSG" "${PREFIX}-${ENV}-${name}-nsg" \
    "$(az network vnet subnet show -g "$RG" --vnet-name "${PREFIX}-${ENV}-vnet" -n "${PREFIX}-${ENV}-${name}-snet" --query 'networkSecurityGroup.id' -o tsv | awk -F/ '{print $NF}')"
done
check "app NSG allows 443 from Internet" "Allow 443 Internet" \
  "$(az network nsg rule show -g "$RG" --nsg-name "${PREFIX}-${ENV}-app-nsg" -n allow-https-from-internet --query '[access,destinationPortRange,sourceAddressPrefix]' -o tsv | tr '\t\n' '  ' | xargs)"
check "data NSG allows the app subnet" "Allow 10.10.1.0/24" \
  "$(az network nsg rule show -g "$RG" --nsg-name "${PREFIX}-${ENV}-data-nsg" -n allow-from-app-subnet --query '[access,sourceAddressPrefix]' -o tsv | tr '\t\n' '  ' | xargs)"
check "data NSG denies other VNet traffic" "Deny 4000" \
  "$(az network nsg rule show -g "$RG" --nsg-name "${PREFIX}-${ENV}-data-nsg" -n deny-other-vnet-traffic --query '[access,priority]' -o tsv | tr '\t\n' '  ' | xargs)"
check "policy assignments on the RG" "2" \
  "$(az policy assignment list -g "$RG" --query 'length(@)' -o tsv)"

echo "--- idempotency"
set +e
terraform plan "${VARS[@]}" -detailed-exitcode -input=false -no-color >/dev/null
code=$?
set -e
check "second plan has no changes (exit 0)" "0" "$code"

echo "--- policy probes"
probe() { # probe <name> <location> [tags...] -> prints "allowed" or "denied"
  local out
  if out=$(az network nsg create -g "$RG" -n "$1" -l "$2" ${3:+--tags "$3"} -o none 2>&1); then
    echo allowed
  elif grep -q RequestDisallowedByPolicy <<<"$out"; then
    echo denied
  else
    echo "error: $out" >&2; echo error
  fi
}
check "NSG without the required tag is denied" "denied" "$(probe probe-notag eastus)"
check "NSG in a region not allowed is denied" "denied" "$(probe probe-westus westus "environment=${ENV}")"
check "tagged NSG in an allowed region is accepted" "allowed" "$(probe probe-ok eastus "environment=${ENV}")"
