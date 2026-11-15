# Upgrade Istio: control plane first, then the proxies

## What we do

You upgrade Istio in **cluster b** from 1.29.9 to 1.30.8 with Helm, in the same order as in production: first the control plane, then the data plane (gateway and sidecars). A loop calls Bookinfo all the time, so you see whether the upgrade costs requests.

Measured in our lab in a cluster that was **not** connected to another cluster and had no VM. Not tested: the upgrade of one cluster while the two clusters are one mesh, and the upgrade of the sidecar on a VM (a new `istio-sidecar.deb`).

This is an in-place upgrade: the new `istiod` replaces the old one. The other way, two control planes side by side, is on the next page: [Upgrade Istio with revisions](02-upgrade-istio-with-revisions.md).

The steps below use Helm, because the lab is installed with Helm. The same upgrade with `istioctl` is at the end of the page.

All commands run on your bastion host as your lab user.

```
export CTX=cluster-b
export NEW=1.30.8
mkdir -p ~/upgrade && cd ~/upgrade
```

## Step 1: Before you start

Which versions are there, and is the cluster ready?

```
helm repo add istio https://istio-release.storage.googleapis.com/charts --force-update
helm repo update
helm search repo istio/istiod --versions | head -4
istioctl --context $CTX x precheck
istioctl --context $CTX version
```

```
No issues found when checking the cluster. Istio is safe to install or upgrade!
```

```
client version: 1.29.9
control plane version: 1.29.9
data plane version: 1.29.9 (7 proxies)
```

Save the current settings. The upgrade should run with the same values as the installation:

```
helm --kube-context $CTX -n istio-system get values istiod -o yaml > istiod-values.yaml
helm --kube-context $CTX -n istio-ingress get values istio-ingressgateway -o yaml > gateway-values.yaml
cat istiod-values.yaml
```

```
global:
  caAddress: cert-manager-istio-csr.cert-manager.svc:443
  meshID: mesh-tln3
  multiCluster:
    clusterName: cluster-b
  network: net1
pilot:
  env:
    ENABLE_CA_SERVER: "false"
  resources:
    requests:
      cpu: 200m
      memory: 512Mi
```

## Step 2: Start a loop of calls

In a **second terminal**, also on the bastion host:

```
GW=$(kubectl --context cluster-b -n istio-ingress get svc istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
while true; do curl -6 -s -o /dev/null -m 4 -w "%{http_code}\n" "http://[$GW]/productpage"; sleep 0.5; done | tee ~/upgrade/calls.log
```

Leave it running until the end.

## Step 3: Upgrade the control plane

First the custom resource definitions, then `istiod`:

```
helm --kube-context $CTX upgrade istio-base istio/base -n istio-system --version $NEW --wait
helm --kube-context $CTX upgrade istiod istio/istiod -n istio-system --version $NEW -f istiod-values.yaml --wait --timeout 5m
```

In our lab the two commands took 14 seconds together.

```
istioctl --context $CTX version
```

```
client version: 1.29.9
control plane version: 1.30.8
data plane version: 1.29.9 (5 proxies)
```

The control plane is new, the proxies are still old. In our lab the new `istiod` served the old proxies without an error. Right after the upgrade not all proxies are in the list yet (5 of 7 in our lab), they reconnect to the new `istiod` one after the other.

```
istioctl --context $CTX proxy-status
```

```
NAME                                                    CLUSTER       ISTIOD                      VERSION     SUBSCRIBED TYPES
details-v1-6cc9f5cc44-959w6.default                     cluster-b     istiod-58c7fc7dcb-tr7g8     1.29.9      4 (CDS,LDS,EDS,RDS)
istio-ingressgateway-5dc49cc6bf-2n4lx.istio-ingress     cluster-b     istiod-58c7fc7dcb-tr7g8     1.29.9      4 (CDS,LDS,EDS,RDS)
productpage-v1-7f885b46fc-fw2pc.default                 cluster-b     istiod-58c7fc7dcb-tr7g8     1.29.9      4 (CDS,LDS,EDS,RDS)
ratings-v1-77b8b6df5b-lzxvp.default                     cluster-b     istiod-58c7fc7dcb-tr7g8     1.29.9      4 (CDS,LDS,EDS,RDS)
reviews-v1-fdbf79cd8-wvqrl.default                      cluster-b     istiod-58c7fc7dcb-tr7g8     1.29.9      4 (CDS,LDS,EDS,RDS)
```

The column `VERSION` is your to-do list for the next step.

## Step 4: Upgrade the data plane

The gateway is its own Helm release:

```
helm --kube-context $CTX upgrade istio-ingressgateway istio/gateway -n istio-ingress --version $NEW -f gateway-values.yaml --wait --timeout 5m
```

A sidecar is injected when its pod is created. So a pod gets the new sidecar only when it is created again:

```
kubectl --context $CTX rollout restart deploy -n default
kubectl --context $CTX rollout status deploy/productpage-v1
```

```
istioctl --context $CTX proxy-status
```

```
NAME                                                    CLUSTER       ISTIOD                      VERSION     SUBSCRIBED TYPES
details-v1-5fbd4f6d86-pvxzz.default                     cluster-b     istiod-58c7fc7dcb-tr7g8     1.30.8      4 (CDS,LDS,EDS,RDS)
istio-ingressgateway-7df6978b45-grxjk.istio-ingress     cluster-b     istiod-58c7fc7dcb-tr7g8     1.30.8      4 (CDS,LDS,EDS,RDS)
productpage-v1-59db8f9668-7nwkr.default                 cluster-b     istiod-58c7fc7dcb-tr7g8     1.30.8      4 (CDS,LDS,EDS,RDS)
ratings-v1-6558d57cc4-t2m5k.default                     cluster-b     istiod-58c7fc7dcb-tr7g8     1.30.8      4 (CDS,LDS,EDS,RDS)
reviews-v1-7bdcfb4cd-npvnk.default                      cluster-b     istiod-58c7fc7dcb-tr7g8     1.30.8      4 (CDS,LDS,EDS,RDS)
reviews-v2-749fbf55bb-rng4z.default                     cluster-b     istiod-58c7fc7dcb-tr7g8     1.30.8      4 (CDS,LDS,EDS,RDS)
reviews-v3-5c46d4d586-fmq7v.default                     cluster-b     istiod-58c7fc7dcb-tr7g8     1.30.8      4 (CDS,LDS,EDS,RDS)
```

Everything is on 1.30.8.

## Step 5: Did it cost requests?

Stop the loop in the second terminal (Ctrl+C) and count:

```
sort ~/upgrade/calls.log | uniq -c
```

```
     96 200
```

In our lab: 96 calls during the whole upgrade, all `200`. One replica of every deployment, two calls per second: this is a small test, not a proof for production load.

## The same with istioctl

`istioctl upgrade` is only for an Istio that was installed with `istioctl`. The Istio documentation lists as a prerequisite: "Your Istio installation was installed using istioctl." (In-place Upgrades). Our lab is installed with Helm. For this measurement we installed Istio 1.29.9 in cluster b again with `istioctl install -f istio-operator.yaml`, with this file:

```
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  profile: default
  values:
    global:
      caAddress: cert-manager-istio-csr.cert-manager.svc:443
      meshID: mesh-tln14
      multiCluster:
        clusterName: cluster-b
      network: net1
    pilot:
      env:
        ENABLE_CA_SERVER: "false"
  components:
    ingressGateways:
    - name: istio-ingressgateway
      enabled: true
      k8s:
        serviceAnnotations:
          metallb.io/address-pool: ingress-vip
          metallb.io/loadBalancerIPs: "2a01:4f8:c016:2c9c::2:1"
        service:
          type: LoadBalancer
          ipFamilyPolicy: SingleStack
          ipFamilies: [IPv6]
```

With the profile `default` the ingress gateway runs in `istio-system` and belongs to the same installation as `istiod`.

**Get the new istioctl.** The upgrade runs with the `istioctl` of the new version:

```
cd ~/upgrade
curl -6 -fsSL https://storage.googleapis.com/istio-release/releases/$NEW/istioctl-$NEW-linux-amd64.tar.gz | tar xz
./istioctl version --remote=false
./istioctl --context $CTX x precheck
```

```
client version: 1.30.8
```

```
No issues found when checking the cluster. Istio is safe to install or upgrade!
```

**Upgrade the control plane and the gateway.** One command, with the same file as the installation. The Istio documentation: "If you omit the `-f` flag, Istio upgrades using the default profile." Your settings would be gone.

```
./istioctl --context $CTX upgrade -f istio-operator.yaml -y
```

```
WARNING: Istio is being upgraded from 1.29.9 to 1.30.8.
         Running this command will overwrite it; use revisions to upgrade alongside the existing version.
         Before upgrading, you may wish to use 'istioctl x precheck' to check for upgrade warnings.

- Processing resources for Istio core.
✔ Istio core installed ⛵️
- Processing resources for Istiod.
- Processing resources for Istiod. Waiting for Deployment/istio-system/istiod
✔ Istiod installed 🧠
- Processing resources for Ingress gateways.
- Processing resources for Ingress gateways. Waiting for Deployment/istio-system/istio-ingressgat...
✔ Ingress gateways installed 🛬
- Pruning removed resources
✔ Installation complete
```

In our lab this took 15 seconds. Before these lines `istioctl` printed a hint about Calico (`bpfConnectTimeLoadBalancing`), which we did not look into. Different from Helm: there is no separate step for the custom resource definitions and none for the gateway.

```
./istioctl --context $CTX version
```

```
client version: 1.30.8
control plane version: 1.30.8
data plane version: 1.29.9 (7 proxies), 1.30.8 (1 proxies)
```

The gateway is already new, the sidecars are still old.

**Upgrade the sidecars.** The same as with Helm:

```
kubectl --context $CTX rollout restart deploy -n default
kubectl --context $CTX rollout status deploy/productpage-v1
./istioctl --context $CTX proxy-status
```

```
NAME                                                  CLUSTER       ISTIOD                      VERSION     SUBSCRIBED TYPES
details-v1-7b4cc45bdf-sx9rd.default                   cluster-b     istiod-56c97c4b9d-njpvc     1.30.8      4 (CDS,LDS,EDS,RDS)
istio-ingressgateway-cdd65c549-xvfrt.istio-system     cluster-b     istiod-56c97c4b9d-njpvc     1.30.8      4 (CDS,LDS,EDS,RDS)
productpage-v1-78c8db86d9-sh7qd.default               cluster-b     istiod-56c97c4b9d-njpvc     1.30.8      4 (CDS,LDS,EDS,RDS)
ratings-v1-5647d764fc-7n9ww.default                   cluster-b     istiod-56c97c4b9d-njpvc     1.30.8      4 (CDS,LDS,EDS,RDS)
reviews-v1-55f9bcc69-kthfl.default                    cluster-b     istiod-56c97c4b9d-njpvc     1.30.8      4 (CDS,LDS,EDS,RDS)
reviews-v2-79c86bcfbf-4l9jr.default                   cluster-b     istiod-56c97c4b9d-njpvc     1.30.8      4 (CDS,LDS,EDS,RDS)
reviews-v3-674f7749f7-2tfnb.default                   cluster-b     istiod-56c97c4b9d-njpvc     1.30.8      4 (CDS,LDS,EDS,RDS)
```

**Did it cost requests?** We ran the upgrade with `istioctl` twice, with the same loop of calls:

| Run | Calls | Failed | When |
|---|---|---|---|
| 1 | 68 | 1 | while the pods in `default` restarted |
| 2 | 96 | 0 | |

The failed call had no HTTP status (`000`, no answer within 4 seconds). The upgrade of `istiod` and of the gateway cost no call in either run.

## Helm or istioctl: what is different

| | Helm | istioctl |
|---|---|---|
| Works for | an Istio installed with Helm | an Istio installed with `istioctl` |
| Custom resource definitions | own step (`istio-base`) | part of `istioctl upgrade` |
| Gateway | own step (own release) | part of `istioctl upgrade` (profile `default`) |
| Your settings | `-f istiod-values.yaml` | `-f istio-operator.yaml` |
| Tool version | any Helm, chart version `--version` | the `istioctl` of the new version |
| Sidecars | restart the pods | restart the pods |

## What to take away

* **Order:** CRDs, `istiod`, then gateways and sidecars. Never the proxies before the control plane.
* **The upgrade of the control plane cost no call in our lab. The restart of the pods can:** with one replica per deployment, one call failed in one of three runs.
* **A sidecar is only as new as its pod.** After the upgrade of `istiod` nothing changes in a running pod. `istioctl proxy-status` shows in the column `VERSION` who is still old.
* **Pass the saved values explicitly** (cluster name, network, certificate authority), so that you know what the new release runs with.
* **cert-manager and istio-csr** are separate releases and were not touched. The sidecars got their certificates as before.
* **A VM is a pod that nobody restarts for you:** its sidecar stays on the old version until you install the new package on the VM.

After the upgrade with Helm, `istioctl` on the bastion host is still 1.29.9. It should be upgraded, too (we did not do that in the Helm run).

Next: [Upgrade Istio with revisions](02-upgrade-istio-with-revisions.md)
