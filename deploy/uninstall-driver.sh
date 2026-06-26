#!/usr/bin/env bash

# Copyright 2020 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euo pipefail

if [[ "$#" -gt 1 ]]; then
  echo "Usage: $0 [branch|local|url]" >&2
  exit 1
fi

# Optional [branch|local|url] argument selects the manifest source. The default
# (no argument) stays the local checkout -- preserving the behavior relied on by
# the docs and test/scale/run_test.py (which pairs this with
# `install-driver.sh local`). Unlike install-driver.sh (which defaults to remote
# `main`), the uninstaller keeps a local default for backward compatibility.
# `git rev-parse` runs only on the local paths, so a branch/url argument works
# outside a git checkout.
#   (no arg) | local : use the local checkout's manifests
#   <branch>         : use manifests from that remote branch
#   http...          : use manifests from that base URL
if [[ "$#" -eq 0 || "${1:-}" == "local" ]]; then
  repo="$(git rev-parse --show-toplevel)/deploy"
elif [[ "${1}" == http* ]]; then
  repo="${1}/deploy"
else
  repo="https://raw.githubusercontent.com/kubernetes-sigs/azurelustre-csi-driver/${1}/deploy"
fi

# Validate the manifest source up front (mirrors install-driver.sh) so a mistyped
# branch or bad URL fails fast here, instead of aborting partway through teardown
# (the DaemonSet deletion below runs before the `delete -f` lines, and
# --ignore-not-found does not suppress a source-fetch error).
probe="${repo}/csi-azurelustre-controller.yaml"
if [[ "${repo}" == http* ]]; then
  if ! curl -L -Is --fail "${probe}" > /dev/null; then
    echo "Unknown repository: ${probe} does not exist." >&2
    exit 1
  fi
elif [[ ! -f "${probe}" ]]; then
  echo "Manifest not found: ${probe}" >&2
  exit 1
fi

for i in $(kubectl get daemonsets.apps -n kube-system -l app=csi-azurelustre-node -o name); do
  kubectl delete -n kube-system "${i}"
done

echo "Uninstalling Azure Lustre CSI driver, repo: ${repo} ..."
kubectl delete -f "${repo}"/csi-azurelustre-controller.yaml --ignore-not-found
kubectl delete -f "${repo}"/csi-azurelustre-node-jammy.yaml --ignore-not-found
kubectl delete -f "${repo}"/csi-azurelustre-node-noble.yaml --ignore-not-found
kubectl delete -f "${repo}"/csi-azurelustre-node-azurelinux3.yaml --ignore-not-found
kubectl delete -f "${repo}"/csi-azurelustre-driver.yaml --ignore-not-found
kubectl delete -f "${repo}"/rbac-csi-azurelustre-controller.yaml --ignore-not-found
kubectl delete -f "${repo}"/rbac-csi-azurelustre-node.yaml --ignore-not-found
# Mirror install-driver.sh: also remove the legacy un-prefixed RBAC left by
# installs that predate the csi- rename. The rbac-*.yaml files above only carry
# the current csi-azurelustre-* names, so these would otherwise be orphaned.
kubectl delete clusterrolebinding azurelustre-csi-provisioner-binding --ignore-not-found
kubectl delete clusterrole azurelustre-external-provisioner-role --ignore-not-found
kubectl delete configmap csi-azurelustre-entrypoint -n kube-system --ignore-not-found
echo 'Uninstalled Azure Lustre CSI driver successfully.'
