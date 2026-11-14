#!/usr/bin/env bash
# Give the VM a fresh token, from the first cluster whose control plane is alive.
# This is a stand-in for an automation job (for example an AWX playbook) that would run every few minutes.
#
# Run this on your bastion host as your lab user:
#   ./vm-refresh-token.sh
#
# What it does:
#   1. Look for a cluster where istiod and istio-csr are running: first cluster a, then cluster b.
#   2. Ask this cluster for a token of the service account of the VM (valid for one hour, see DURATION).
#   3. Put the token on the VM, readable for the user istio-proxy.
#   4. If the VM was registered with the other cluster: write the addresses of istiod and istio-csr of the new cluster
#      into /etc/hosts (only this cluster), set the cluster ID and restart the sidecar.
#
# Why only one cluster in /etc/hosts: with the addresses of both clusters the agent does not take the first line.
# It prefers the address that is most similar to its own (measured in our lab). A token is only valid for the cluster
# that created it, so the VM must talk to exactly this cluster.
#
# Settings (optional): VM=a-vm1  CLUSTERS="cluster-a cluster-b"  NS=vm  SA=diameter-adapter
#                      DURATION=1h (lifetime of the token, 10m is the shortest Kubernetes accepts)
set -euo pipefail
VM=${VM:-a-vm1}; CLUSTERS=${CLUSTERS:-cluster-a cluster-b}; NS=${NS:-vm}; SA=${SA:-diameter-adapter}; DURATION=${DURATION:-1h}

ready() {  # ready <context> <namespace> <deployment>: true if at least one replica is ready
  local n
  n=$(kubectl --context "$1" --request-timeout=5s -n "$2" get deploy "$3" -o jsonpath='{.status.readyReplicas}' 2>/dev/null) || return 1
  [ "${n:-0}" -ge 1 ]
}

PICK=
for c in $CLUSTERS; do
  if ready "$c" istio-system istiod && ready "$c" cert-manager cert-manager-istio-csr; then PICK=$c; break; fi
  echo "$c: control plane not ready, trying the next cluster"
done
[ -n "$PICK" ] || { echo "No cluster with a running control plane. The VM keeps what it has."; exit 1; }
echo "Token from: $PICK (valid for $DURATION)"

T=$(mktemp); trap 'rm -f "$T"' EXIT
kubectl --context "$PICK" create token "$SA" -n "$NS" --audience istio-ca --duration "$DURATION" > "$T"
scp -q "$T" "$VM:/var/run/secrets/tokens/istio-token"
ssh "$VM" "chown istio-proxy: /var/run/secrets/tokens/istio-token; chmod 600 /var/run/secrets/tokens/istio-token"

OLD=$(ssh "$VM" "grep '^ISTIO_META_CLUSTER_ID=' /var/lib/istio/envoy/cluster.env | cut -d\\' -f2")
ISTIOD_ADDR=$(kubectl --context "$PICK" -n istio-system get svc istiod-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
CSR_ADDR=$(kubectl --context "$PICK" -n cert-manager get svc istio-csr-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
[ -n "$ISTIOD_ADDR" ] && [ -n "$CSR_ADDR" ] || { echo "$PICK has no istiod-lb or istio-csr-lb: prepare the cluster for VMs first"; exit 1; }
NOW=$(ssh "$VM" "grep -c -E '^($ISTIOD_ADDR istiod.istio-system.svc|$CSR_ADDR cert-manager-istio-csr.cert-manager.svc)\$' /etc/hosts; grep -c -E 'istiod.istio-system.svc|cert-manager-istio-csr.cert-manager.svc' /etc/hosts" | tr '\n' ' ')
if [ "$OLD" != "$PICK" ] || [ "$NOW" != "2 2 " ]; then
  echo "The VM was registered with $OLD: point it to $PICK ($ISTIOD_ADDR, $CSR_ADDR), set the cluster ID and restart the sidecar"
  ssh "$VM" "sed -i '/istiod.istio-system.svc/d; /cert-manager-istio-csr.cert-manager.svc/d' /etc/hosts
echo '$ISTIOD_ADDR istiod.istio-system.svc' >> /etc/hosts
echo '$CSR_ADDR cert-manager-istio-csr.cert-manager.svc' >> /etc/hosts
sed -i \"s/^ISTIO_META_CLUSTER_ID=.*/ISTIO_META_CLUSTER_ID='$PICK'/\" /var/lib/istio/envoy/cluster.env
systemctl restart istio"
else
  echo "The VM is registered with $PICK already: token replaced, no restart"
fi
