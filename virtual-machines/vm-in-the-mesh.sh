#!/usr/bin/env bash
# Add a virtual machine to the mesh, step by step.
#
# Run this on your bastion host as your lab user (tln1, tln2, ...).
# Every step shows the commands first. Press ENTER and the script runs exactly these commands.
# You can type the same commands by hand, the script only saves you the typing.
#
#   ./vm-in-the-mesh.sh                 all steps, one after the other (VM with IPv6 only, the default)
#   DUAL_STACK=1 ./vm-in-the-mesh.sh    the optional variant: the VM also has an IPv4 address (dual stack switches)
#   ./vm-in-the-mesh.sh cleanup         remove everything this script created
#
# Settings (optional): VM=a-vm1  CTX_A=cluster-a  CTX_B=cluster-b  NOPAUSE=1 (no ENTER prompts)  DUAL_STACK=1
set -eEo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$HOME/vm-in-the-mesh}
export DUAL_STACK=${DUAL_STACK:-0}
mkdir -p "$WORK"
cp "$HERE/vm-echo-server.py" "$WORK/"
cd "$WORK"

trap 'echo; echo "!! This step failed. Read the message above, fix the problem and start the script again." >&2' ERR

if [ -t 1 ]; then B=$'\e[1m'; C=$'\e[36m'; G=$'\e[32m'; N=$'\e[0m'; else B=; C=; G=; N=; fi
N_STEP=0
exec 3<&0   # keep the keyboard, go() reads its commands from a here-document

pause() {
  [ -n "${NOPAUSE:-}" ] && return 0
  printf '\n%s... to continue press ENTER%s ' "$B" "$N"
  read -r _ <&3 || true
}

# step "title" "explanation line" ...
step() {
  N_STEP=$((N_STEP + 1))
  printf '\n%s================================================================%s\n' "$B" "$N"
  printf '%sStep %s: %s%s\n' "$B" "$N_STEP" "$1" "$N"
  shift
  for line in "$@"; do printf '%s\n' "$line"; done
}

# go: reads the commands from stdin, shows them, waits for ENTER, then runs them
go() {
  local text
  text=$(cat)
  echo
  printf '%s\n' "$text" | sed "s/^/  ${C}/; s/\$/${N}/"
  pause
  echo
  eval "$text"
}

# ---------------------------------------------------------------------------
if [ "${1:-}" = cleanup ]; then
  CTX_A=${CTX_A:-cluster-a}; CTX_B=${CTX_B:-cluster-b}; VM=${VM:-a-vm1}
  step "Clean up" "Removes the namespace vm, the test pods and the sidecar on the VM. The settings of istiod stay."
  go <<'EOF'
kubectl --context $CTX_A delete namespace vm --ignore-not-found
kubectl --context $CTX_B delete namespace vm --ignore-not-found
kubectl --context $CTX_A delete deploy client --ignore-not-found
kubectl --context $CTX_B delete deploy client --ignore-not-found
ssh $VM "systemctl stop istio vm-echo 2>/dev/null; sed -i '/istiod.istio-system.svc/d' /etc/hosts; rm -rf /root/vmfiles /var/lib/istio/envoy/cluster.env /etc/certs/root-cert.pem /var/run/secrets/tokens/istio-token"
rm -rf vmfiles
EOF
  printf '\n%sDone.%s\n' "$G" "$N"
  exit 0
fi

# ---------------------------------------------------------------------------
printf '%sAdd a virtual machine to the mesh%s\n' "$B" "$N"
echo "Picture: images/vm-in-the-mesh.svg. Files of this run are in $WORK (vmfiles contains a token, do not share it)."

step "Settings" \
  "Two clusters, one VM. The VM is called a-vm1 and joins cluster a (cluster b finds it through the mesh)." \
  "The VM must have an IPv6 address only (its IPv4 address is switched off). We read the addresses from the VM."
go <<'EOF'
export CTX_A=${CTX_A:-cluster-a}
export CTX_B=${CTX_B:-cluster-b}
export VM=${VM:-a-vm1}
export ISTIO_VERSION=$(istioctl version --remote=false | awk '{print $3}')
export VM_IP=$(ssh $VM "ip -6 -o addr show dev eth0 scope global" | awk '{print $4}' | cut -d/ -f1 | head -1)
export VM_IP4=$(ssh $VM "ip -4 -o addr show dev eth0 scope global" | awk '{print $4}' | head -1)
echo "Istio $ISTIO_VERSION, VM $VM has the IPv6 address $VM_IP and the IPv4 address: ${VM_IP4:-none}"
EOF
if [ -n "${VM_IP4:-}" ] && [ "$DUAL_STACK" != 1 ]; then
  printf '\n%s!! %s has the IPv4 address %s. For IPv6 only switch it off first (ask the trainer), or run the dual stack variant: DUAL_STACK=1 ./vm-in-the-mesh.sh%s\n' "$B" "$VM" "$VM_IP4" "$N" >&2
  exit 1
fi
if [ -z "${VM_IP4:-}" ] && [ "$DUAL_STACK" = 1 ]; then
  printf '\n%s!! DUAL_STACK=1 needs a VM with an IPv4 address, but %s has none. Switch IPv4 on first (ask the trainer), or run without DUAL_STACK.%s\n' "$B" "$VM" "$N" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
step "Make istiod ready for VMs" \
  "The VM must reach istiod from outside the cluster, so istiod gets a fixed LoadBalancer address (port 15012)." \
  "Two switches in istiod: auto registration (istiod creates the WorkloadEntry for us) and DNS proxy (the VM resolves" \
  "service names of the cluster). With DUAL_STACK=1 a third one, ISTIO_DUAL_STACK, for a VM with IPv4 and IPv6."

istiod_ready() {
  local env
  env=$(kubectl --context "$CTX_A" -n istio-system get deploy istiod -o jsonpath='{.spec.template.spec.containers[0].env[*].name}')
  [[ "$env" == *PILOT_ENABLE_WORKLOAD_ENTRY_AUTOREGISTRATION* ]] || return 1
  [[ "$DUAL_STACK" != 1 || "$env" == *ISTIO_DUAL_STACK* ]] &&
    kubectl --context "$CTX_A" -n istio-system get svc istiod-lb > /dev/null 2>&1
}

if istiod_ready; then
  echo "Already done in this lab, nothing to do."
  export ISTIOD_ADDR=$(kubectl --context "$CTX_A" -n istio-system get svc istiod-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  echo "Address of istiod for the VM: $ISTIOD_ADDR"
  pause
else
  helm_cmds() {
    cat <<'EOF'
helm repo add istio https://istio-release.storage.googleapis.com/charts --force-update
helm --kube-context $CTX_A upgrade istiod istio/istiod -n istio-system --version $ISTIO_VERSION --reuse-values --wait \
  --set-string pilot.env.PILOT_ENABLE_WORKLOAD_ENTRY_AUTOREGISTRATION=true \
EOF
    if [ "$DUAL_STACK" = 1 ]; then cat <<'EOF'
  --set-string pilot.env.ISTIO_DUAL_STACK=true \
  --set-string meshConfig.defaultConfig.proxyMetadata.ISTIO_DUAL_STACK=true \
EOF
    fi
    cat <<'EOF'
  --set-string meshConfig.defaultConfig.proxyMetadata.ISTIO_META_DNS_CAPTURE=true \
  --set-string meshConfig.defaultConfig.proxyMetadata.ISTIO_META_DNS_AUTO_ALLOCATE=true
EOF
  }
  helm_cmds | go
  echo "The fixed address: next to the address of the ingress gateway (same /64 as the control plane)."
  go <<'EOF'
export CP_NODE=$(kubectl --context $CTX_A get node -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].metadata.name}')
export INGRESS_ADDR=$(kubectl --context $CTX_A -n istio-ingress get svc istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export ISTIOD_ADDR=${INGRESS_ADDR%:*}:2
echo "Address of istiod for the VM: $ISTIOD_ADDR"
kubectl --context $CTX_A apply -f - <<YAML
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata: {name: istiod-vip, namespace: metallb-system}
spec: {addresses: ["$ISTIOD_ADDR/128"], autoAssign: false}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata: {name: istiod-vip, namespace: metallb-system}
spec:
  ipAddressPools: [istiod-vip]
  nodeSelectors: [{matchLabels: {kubernetes.io/hostname: $CP_NODE}}]
---
apiVersion: v1
kind: Service
metadata:
  name: istiod-lb
  namespace: istio-system
  annotations: {metallb.io/loadBalancerIPs: "$ISTIOD_ADDR", metallb.io/address-pool: istiod-vip}
spec:
  type: LoadBalancer
  ipFamilyPolicy: SingleStack
  ipFamilies: [IPv6]
  selector: {app: istiod, istio: pilot}
  ports: [{name: tls-istiod, port: 15012, targetPort: 15012}]
YAML
sleep 5
kubectl --context $CTX_A -n istio-system get svc istiod-lb
EOF
fi

# ---------------------------------------------------------------------------
step "Create the objects for the VM" \
  "Namespace, service account and service (in both clusters), plus the WorkloadGroup (only cluster a)." \
  "The WorkloadGroup is the template for the VM. The Service finds the VM by the label app=diameter-adapter." \
  "At the end we wait until istiod has put its root certificate into the new namespace."
go <<'EOF'
cat > 01-vm-objects.yml <<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: vm
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: diameter-adapter
  namespace: vm
---
apiVersion: v1
kind: Service
metadata:
  name: diameter-adapter
  namespace: vm
  labels:
    app: diameter-adapter
spec:
  ipFamilyPolicy: SingleStack
  ipFamilies: [IPv6]
  ports:
    - name: http
      port: 8000
      targetPort: 8000
  selector:
    app: diameter-adapter
YAML
cat > 02-workloadgroup.yml <<YAML
apiVersion: networking.istio.io/v1
kind: WorkloadGroup
metadata:
  name: diameter-adapter
  namespace: vm
spec:
  metadata:
    labels:
      app: diameter-adapter
  template:
    serviceAccount: diameter-adapter
    network: net1
    ports:
      http: 8000
YAML
kubectl --context $CTX_A apply -f 01-vm-objects.yml -f 02-workloadgroup.yml
kubectl --context $CTX_B apply -f 01-vm-objects.yml
kubectl --context $CTX_A -n vm wait --for=create cm/istio-ca-root-cert --timeout=60s
EOF

# ---------------------------------------------------------------------------
step "Create the files for the VM" \
  "istioctl writes everything the VM needs: root certificate, a token, the mesh configuration, the address of istiod." \
  "The file istio-token is a secret. Do not print it and do not commit it."
go <<'EOF'
rm -rf vmfiles
istioctl --context $CTX_A x workload entry configure -f 02-workloadgroup.yml -o vmfiles --clusterID cluster-a --ingressIP $ISTIOD_ADDR --autoregister
ls vmfiles
scp -q -r vmfiles vm-echo-server.py $VM:/root/
EOF

# ---------------------------------------------------------------------------
step "Install the sidecar on the VM and start it" \
  "Everything below runs on the VM (through ssh): install the package, put the files in place, start the sidecar" \
  "and the application. The VM has IPv6 only, so the files from istioctl are all the sidecar needs."
[ "$DUAL_STACK" != 1 ] || echo "Dual stack variant: we also add ISTIO_SVC_IP (the address to register) and DUAL_STACK (IPv6 iptables rules) to cluster.env."
sidecar_cmds() {
  cat <<'EOF'
ssh $VM bash -s <<VMSTEPS
set -e
curl -fsSL https://storage.googleapis.com/istio-release/releases/$ISTIO_VERSION/deb/istio-sidecar.deb -o /tmp/istio-sidecar.deb
dpkg -i /tmp/istio-sidecar.deb
mkdir -p --mode=1777 /etc/certs /var/run/secrets/tokens /var/run/secrets/istio
mkdir -p /etc/istio/proxy /etc/istio/config /var/lib/istio/envoy
cd /root/vmfiles
cp root-cert.pem /etc/certs/root-cert.pem
cp istio-token /var/run/secrets/tokens/istio-token
cp cluster.env /var/lib/istio/envoy/cluster.env
cp mesh.yaml /etc/istio/config/mesh
cat hosts >> /etc/hosts
EOF
  if [ "$DUAL_STACK" = 1 ]; then cat <<'EOF'
echo "ISTIO_SVC_IP='$VM_IP'" >> /var/lib/istio/envoy/cluster.env
echo "DUAL_STACK='true'" >> /var/lib/istio/envoy/cluster.env
EOF
  fi
  cat <<'EOF'
chown -R istio-proxy: /var/lib/istio /etc/certs /etc/istio/proxy /etc/istio/config /var/run/secrets
systemctl start istio
systemd-run --unit vm-echo python3 /root/vm-echo-server.py
VMSTEPS
EOF
}
sidecar_cmds | go

# ---------------------------------------------------------------------------
step "Check: is the VM in the mesh?" \
  "The VM must show up in proxy-status, and istiod must have created a WorkloadEntry with the IPv6 address of the VM." \
  "This only shows that the VM is connected to istiod. The next step shows that traffic works."
go <<'EOF'
sleep 10
istioctl --context $CTX_A proxy-status | grep -E "NAME|vm"
kubectl --context $CTX_A get workloadentry -n vm
EOF

# ---------------------------------------------------------------------------
step "Call the VM from a pod" \
  "A test pod with a sidecar calls the service diameter-adapter. The answer comes from the VM." \
  "The header x-forwarded-client-cert shows the identities of both sides: mTLS between the pod and the VM."
go <<'EOF'
kubectl --context $CTX_A create deploy client --image=curlimages/curl:8.11.1 -- sleep infinity
kubectl --context $CTX_A rollout status deploy/client
kubectl --context $CTX_A exec deploy/client -c curl -- curl -s -m 8 -w "\nHTTP %{http_code}\n" http://diameter-adapter.vm.svc.cluster.local:8000/
EOF

# ---------------------------------------------------------------------------
step "Call a service in the cluster from the VM" \
  "The other direction: the VM calls productpage (Bookinfo). The sidecar of the VM resolves the name (DNS proxy)."
go <<'EOF'
ssh $VM 'curl -s -m 8 -o /dev/null -w "HTTP %{http_code}\n" http://productpage.default.svc.cluster.local:9080/productpage'
EOF

# ---------------------------------------------------------------------------
step "Call the VM from cluster b" \
  "The VM is registered in cluster a. A pod in cluster b finds it, too: both clusters are one mesh."
go <<'EOF'
kubectl --context $CTX_B create deploy client --image=curlimages/curl:8.11.1 -- sleep infinity
kubectl --context $CTX_B rollout status deploy/client
kubectl --context $CTX_B exec deploy/client -c curl -- curl -s -m 8 -w "\nHTTP %{http_code}\n" http://diameter-adapter.vm.svc.cluster.local:8000/
EOF

printf '\n%sDone: the VM is part of the mesh. Remove everything with: ./vm-in-the-mesh.sh cleanup%s\n' "$G" "$N"
