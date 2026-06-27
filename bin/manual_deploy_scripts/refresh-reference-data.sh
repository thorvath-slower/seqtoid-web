#!/usr/bin/env bash
# On-demand refresh of taxon-lineage reference data + its Elasticsearch index, DECOUPLED from a web deploy
# (#334 / feature 20029). Runs `reference_data:refresh[version,file_key]` as a one-off czecs task against
# the CURRENTLY-DEPLOYED web task definition for the target environment — no new image build, no service
# upgrade, no full destroy+rebuild. Mirrors the czecs-task-rake mechanism in deploy-web.sh.
#
# Usage: refresh-reference-data.sh <env> <version> <file_key>
#   env       dev|staging|prod|sandbox
#   version   taxon lineage version, e.g. 2024-02-06
#   file_key  S3 key under S3_DATABASE_BUCKET,
#             e.g. ncbi-indexes-prod/2024-02-06/index-generation-2/taxon_lineages_2024_slice.csv
set -euo pipefail

env=${1:?env required (dev|staging|prod|sandbox)}
version=${2:?version required (e.g. 2024-02-06)}
file_key=${3:?file_key required (S3 key under S3_DATABASE_BUCKET)}

cd "$(dirname "$0")"

# Download czecs (same pin as deploy-web.sh).
os=$(uname | tr '[:upper:]' '[:lower:]')
trap 'rm -f /tmp/czecs' EXIT
curl -sS -L "https://github.com/chanzuckerberg/czecs/releases/download/v0.1.2/czecs_0.1.2_${os}_amd64.tar.gz" | tar xz -C /tmp czecs

cluster="idseq-${env}-ecs"
balances_file="balances-${env}.json"
service="idseq-${env}-web"

# Resolve the CURRENTLY-DEPLOYED task definition (do NOT register a new one — this is a data refresh,
# not a deploy). This is what decouples the refresh from a code rollout.
task_definition_arn=$(aws ecs describe-services --cluster "$cluster" --services "$service" \
  --query 'services[0].taskDefinition' --output text)
if [[ -z "$task_definition_arn" || "$task_definition_arn" == "None" ]]; then
  echo "ERROR: could not resolve the active task definition for ${service} on ${cluster}." >&2
  echo "Is the web service deployed in ${env}?" >&2
  exit 1
fi
echo "Refreshing reference data on ${cluster} using ${task_definition_arn}"
echo "  version=${version}  file_key=${file_key}"

# Rake args are passed as a single argument to rake inside the rails container (czecs-task-rake.json).
rake_command="reference_data:refresh[${version},${file_key}]"
/tmp/czecs task -f "${balances_file}" --debug --timeout 0 \
  --set taskDefinitionArn="${task_definition_arn}" \
  --set cluster="${cluster}" \
  --set name=rake-task \
  --set rake_command="${rake_command}" \
  czecs-task-rake.json
