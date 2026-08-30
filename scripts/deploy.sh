#!/usr/bin/env bash
set -euo pipefail

: "${DEPLOYMENT_ENVIRONMENT:?Set DEPLOYMENT_ENVIRONMENT to staging or production}"
: "${ECR_REGISTRY:?Set ECR_REGISTRY to the registry returned by the ECR login action}"
: "${IMAGE_TAG:?Set IMAGE_TAG to the immutable image tag to deploy}"
: "${KUBERNETES_NAMESPACE:?Set KUBERNETES_NAMESPACE}"

ECR_REPOSITORY_PREFIX="${ECR_REPOSITORY_PREFIX:-voting-app}"
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-5m}"

case "$DEPLOYMENT_ENVIRONMENT" in
  staging|production) ;;
  *)
    echo "DEPLOYMENT_ENVIRONMENT must be staging or production" >&2
    exit 1
    ;;
esac

if [[ ! "$KUBERNETES_NAMESPACE" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
  echo "KUBERNETES_NAMESPACE is not a valid Kubernetes namespace name" >&2
  exit 1
fi

render_directory="$(mktemp -d)"
trap 'rm -rf "$render_directory"' EXIT
cp -R k8s-specifications "$render_directory/k8s-specifications"
cp -R k8s-overlays "$render_directory/k8s-overlays"

sed -i \
  "s|dockersamples/examplevotingapp_vote|${ECR_REGISTRY}/${ECR_REPOSITORY_PREFIX}/vote:${IMAGE_TAG}|g" \
  "$render_directory/k8s-specifications/vote-deployment.yaml"
sed -i \
  "s|dockersamples/examplevotingapp_result|${ECR_REGISTRY}/${ECR_REPOSITORY_PREFIX}/result:${IMAGE_TAG}|g" \
  "$render_directory/k8s-specifications/result-deployment.yaml"
sed -i \
  "s|dockersamples/examplevotingapp_worker|${ECR_REGISTRY}/${ECR_REPOSITORY_PREFIX}/worker:${IMAGE_TAG}|g" \
  "$render_directory/k8s-specifications/worker-deployment.yaml"

kubectl create namespace "$KUBERNETES_NAMESPACE" \
  --dry-run=client \
  -o yaml | kubectl apply -f -

kubectl apply \
  --namespace "$KUBERNETES_NAMESPACE" \
  --kustomize "$render_directory/k8s-overlays/$DEPLOYMENT_ENVIRONMENT"

for deployment in db redis vote result worker; do
  kubectl rollout status \
    --namespace "$KUBERNETES_NAMESPACE" \
    "deployment/$deployment" \
    --timeout "$ROLLOUT_TIMEOUT"
done

kubectl annotate \
  --namespace "$KUBERNETES_NAMESPACE" \
  deployment/vote deployment/result deployment/worker \
  kubernetes.io/change-cause="Git ${GITHUB_SHA:-$IMAGE_TAG}" \
  --overwrite
