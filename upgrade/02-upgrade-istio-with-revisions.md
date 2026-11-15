# Upgrade Istio with revisions: two control planes side by side

## What we do

You upgrade Istio from 1.29.9 to 1.30.8 without replacing the running `istiod`. A second `istiod` with the new version is installed next to the old one. Then you move the workloads to it, namespace by namespace, and remove the old one at the end. The Istio documentation calls this a canary upgrade and recommends it: "Canary Upgrade is safer than doing an in-place upgrade and is the recommended upgrade method."

A loop calls Bookinfo all the time, so you see whether the upgrade costs requests.

| | In-place ([previous page](01-upgrade-istio-in-place.md)) | With revisions (this page) |
|---|---|---|
| Control planes during the upgrade | one | two |
| A workload moves to the new version | when its pod restarts | when its namespace has the new label **and** its pod restarts |
| Way back | downgrade `istiod` | set the label back, restart the pods |
| Version jump | one minor version | two minor versions are supported |

The last line is from the Istio documentation (Canary Upgrades): "When using revision-based upgrades jumping across two minor versions is supported [...]. This is in contrast to in-place upgrades where it is required to upgrade to each intermediate minor release." We tested one minor version.

Measured in our lab in clusters that were **not** connected to another cluster and had no VM. Not tested: revisions while the two clusters are one mesh, and a VM (see "What to take away").

The steps below use Helm, because the lab is installed with Helm. The same upgrade with `istioctl` is at the end of the page.

All commands run on your bastion host as your lab user.

```
export CTX=cluster-a
export NEW=1.30.8
export REV=1-30-8
mkdir -p ~/upgrade && cd ~/upgrade
```

`REV` is the name of the revision. A dot is not allowed in the name, so the version is written with dashes.

## Step 1: Before you start

```
helm repo add istio https://istio-release.storage.googleapis.com/charts --force-update
helm repo update
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

Save the current settings:

```
helm --kube-context $CTX -n istio-system get values istiod -o yaml > istiod-values.yaml
helm --kube-context $CTX -n istio-ingress get values istio-ingressgateway -o yaml > gateway-values.yaml
```

## Step 2: Start a loop of calls

In a **second terminal**, also on the bastion host:

```
GW=$(kubectl --context cluster-a -n istio-ingress get svc istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
while true; do curl -6 -s -o /dev/null -m 4 -w "%{http_code}\n" "http://[$GW]/productpage"; sleep 0.5; done | tee ~/upgrade/calls.log
```

Leave it running until the end.

## Step 3: Tell istio-csr about the new revision

This step is only needed because cert-manager with `istio-csr` signs the certificate of `istiod`. The new `istiod` gets its own Service, `istiod-1-30-8`, and the certificate must be valid for that name.

```
helm --kube-context $CTX upgrade cert-manager-istio-csr oci://quay.io/jetstack/charts/cert-manager-istio-csr --version v0.19.1 -n cert-manager --reuse-values --set "app.istio.revisions={default,$REV}" --wait
kubectl --context $CTX -n istio-system get certificate istiod -o jsonpath='{.spec.dnsNames}{"\n"}'
```

```
["istiod.istio-system.svc","istiod-1-30-8.istio-system.svc"]
```

**What happens without this step.** In our first run we left it out. The new `istiod` started, but no new pod was created in the namespace that we had moved to the new revision. The event of the ReplicaSet:

```
Error creating: Internal error occurred: failed calling webhook "rev.namespace.sidecar-injector.istio.io": failed to call webhook: Post "https://istiod-1-30-8.istio-system.svc:443/inject?timeout=10s": tls: failed to verify certificate: x509: certificate is valid for istiod.istio-system.svc, not istiod-1-30-8.istio-system.svc
```

The running pods kept working (all calls `200`), only new pods could not be created. After the command above the pods were created again, without a restart of `istiod`.

## Step 4: Install the second control plane

First the custom resource definitions, then a second `istiod` as its own Helm release with `revision`:

```
helm --kube-context $CTX upgrade istio-base istio/base -n istio-system --version $NEW --wait
helm --kube-context $CTX install istiod-$REV istio/istiod -n istio-system --version $NEW --set revision=$REV -f istiod-values.yaml --wait --timeout 5m
```

```
kubectl --context $CTX -n istio-system get pods,svc -L istio.io/rev
```

```
NAME                                READY   STATUS    RESTARTS   AGE    REV
pod/istiod-1-30-8-7c669fc9d-khb6q   1/1     Running   0          2s     1-30-8
pod/istiod-66dbd576c8-gc5fg         1/1     Running   0          108s   default

NAME                    TYPE        CLUSTER-IP           EXTERNAL-IP   PORT(S)                                 AGE    REV
service/istiod          ClusterIP   fd00:10:96::e:6fb6   <none>        15010/TCP,15012/TCP,443/TCP,15014/TCP   108s   default
service/istiod-1-30-8   ClusterIP   fd00:10:96::b:257c   <none>        15010/TCP,15012/TCP,443/TCP,15014/TCP   2s     1-30-8
```

Two control planes, each with its own Service and its own injection webhook (`istio-sidecar-injector` and `istio-sidecar-injector-1-30-8`). Nothing has changed for the workloads. All proxies are still connected to the old `istiod`, the new one has none:

```
istioctl --context $CTX proxy-status
istioctl --context $CTX proxy-status --revision $REV
```

```
NAME                                                    CLUSTER       ISTIOD                      VERSION     SUBSCRIBED TYPES
details-v1-794ff476d7-4th2z.default                     cluster-a     istiod-66dbd576c8-gc5fg     1.29.9      4 (CDS,LDS,EDS,RDS)
istio-ingressgateway-5dc49cc6bf-vr67d.istio-ingress     cluster-a     istiod-66dbd576c8-gc5fg     1.29.9      4 (CDS,LDS,EDS,RDS)
productpage-v1-d8477c48c-76mt7.default                  cluster-a     istiod-66dbd576c8-gc5fg     1.29.9      4 (CDS,LDS,EDS,RDS)
ratings-v1-8588c748c9-2vsd9.default                     cluster-a     istiod-66dbd576c8-gc5fg     1.29.9      4 (CDS,LDS,EDS,RDS)
reviews-v1-58b855fff5-j9w2v.default                     cluster-a     istiod-66dbd576c8-gc5fg     1.29.9      4 (CDS,LDS,EDS,RDS)
reviews-v2-dd5f5b7f5-gdcvx.default                      cluster-a     istiod-66dbd576c8-gc5fg     1.29.9      4 (CDS,LDS,EDS,RDS)
reviews-v3-58f6d99ff9-jmsw6.default                     cluster-a     istiod-66dbd576c8-gc5fg     1.29.9      4 (CDS,LDS,EDS,RDS)
```

```
NAME     CLUSTER     ISTIOD     VERSION     SUBSCRIBED TYPES
```

`istioctl proxy-status` without `--revision` asks only the default control plane. With two control planes you need both commands to see all proxies.

## Step 5: Move a namespace to the new revision

The label decides which `istiod` injects the sidecar. `istio-injection=enabled` means the default revision and must be removed, `istio.io/rev` names the new one. The Istio documentation: "The `istio-injection` label must be removed because it takes precedence".

```
kubectl --context $CTX label namespace default istio-injection- istio.io/rev=$REV
kubectl --context $CTX get ns default -L istio-injection -L istio.io/rev
```

```
NAME      STATUS   AGE   ISTIO-INJECTION   REV
default   Active   22m                     1-30-8
```

The label alone changes nothing in a running pod. Restart the pods:

```
kubectl --context $CTX rollout restart deploy -n default
kubectl --context $CTX rollout status deploy/productpage-v1
istioctl --context $CTX proxy-status
istioctl --context $CTX proxy-status --revision $REV
```

```
NAME                                                    CLUSTER       ISTIOD                      VERSION     SUBSCRIBED TYPES
istio-ingressgateway-5dc49cc6bf-vr67d.istio-ingress     cluster-a     istiod-66dbd576c8-gc5fg     1.29.9      4 (CDS,LDS,EDS,RDS)
```

```
NAME                                        CLUSTER       ISTIOD                            VERSION     SUBSCRIBED TYPES
details-v1-7d5cdd8bdd-s28x8.default         cluster-a     istiod-1-30-8-7c669fc9d-khb6q     1.30.8      4 (CDS,LDS,EDS,RDS)
productpage-v1-8655fcfbbb-jsmwc.default     cluster-a     istiod-1-30-8-7c669fc9d-khb6q     1.30.8      4 (CDS,LDS,EDS,RDS)
ratings-v1-7ff65795d8-vnm27.default         cluster-a     istiod-1-30-8-7c669fc9d-khb6q     1.30.8      4 (CDS,LDS,EDS,RDS)
reviews-v1-5d74c74476-kq89m.default         cluster-a     istiod-1-30-8-7c669fc9d-khb6q     1.30.8      4 (CDS,LDS,EDS,RDS)
reviews-v2-77c7c6996-bgjnp.default          cluster-a     istiod-1-30-8-7c669fc9d-khb6q     1.30.8      4 (CDS,LDS,EDS,RDS)
reviews-v3-7d8cf4ccd4-fgvqt.default         cluster-a     istiod-1-30-8-7c669fc9d-khb6q     1.30.8      4 (CDS,LDS,EDS,RDS)
```

The six sidecars are on the new `istiod`. The gateway (1.29.9, old `istiod`) still sends the calls to them, and they answer: old and new proxies work together.

This is the point where you would stop in production and watch. The way back is the label and one more restart:

```
kubectl --context $CTX label namespace default istio.io/rev- istio-injection=enabled
kubectl --context $CTX rollout restart deploy -n default
```

We did not test this way back in the middle of an upgrade. We used the same two commands when we rebuilt the old state of the cluster for a second run. Do not run them now.

## Step 6: Move the gateway

The gateway has no namespace label. It gets the revision as a value of its Helm release:

```
helm --kube-context $CTX upgrade istio-ingressgateway istio/gateway -n istio-ingress --version $NEW -f gateway-values.yaml --set revision=$REV --wait --timeout 5m
kubectl --context $CTX -n istio-ingress get pods -L istio.io/rev
```

```
NAME                                    READY   STATUS    RESTARTS   AGE   REV
istio-ingressgateway-6dc45f9cb7-6q2fh   1/1     Running   0          25s   1-30-8
```

Now nothing is connected to the old `istiod` any more:

```
istioctl --context $CTX proxy-status
```

```
NAME     CLUSTER     ISTIOD     VERSION     SUBSCRIBED TYPES
```

## Step 7: Make the new revision the default and remove the old control plane

Two things still point to the old `istiod`: the label `istio-injection=enabled` (for namespaces you did not move), and tools like `istioctl proxy-status` without `--revision`. The tag `default` hands both to the new revision. With Helm the tag is a rendered webhook that you apply with `kubectl`:

```
helm --kube-context $CTX template istiod-$REV istio/istiod --version $NEW -s templates/revision-tags-mwc.yaml --set revisionTags="{default}" --set revision=$REV -n istio-system | kubectl --context $CTX apply -f -
istioctl --context $CTX tag list
```

```
mutatingwebhookconfiguration.admissionregistration.k8s.io/istio-revision-tag-default created
```

```
TAG     REVISION NAMESPACES
default 1-30-8   
        default  
```

Then remove the old `istiod` and tell the base chart which revision validates the Istio resources:

```
helm --kube-context $CTX delete istiod -n istio-system
helm --kube-context $CTX upgrade istio-base istio/base -n istio-system --version $NEW --set defaultRevision=$REV --wait
```

```
kubectl --context $CTX -n istio-system get pods,svc -L istio.io/rev
helm --kube-context $CTX ls -n istio-system
```

```
NAME                                READY   STATUS    RESTARTS   AGE   REV
pod/istiod-1-30-8-7c669fc9d-khb6q   1/1     Running   0          65s   1-30-8

NAME                    TYPE        CLUSTER-IP           EXTERNAL-IP   PORT(S)                                 AGE   REV
service/istiod-1-30-8   ClusterIP   fd00:10:96::b:257c   <none>        15010/TCP,15012/TCP,443/TCP,15014/TCP   65s   1-30-8
```

```
NAME         	NAMESPACE   	REVISION	UPDATED                                	STATUS  	CHART        	APP VERSION
istio-base   	istio-system	6       	2026-11-15 12:50:03.965187995 +0000 UTC	deployed	base-1.30.8  	1.30.8     
istiod-1-30-8	istio-system	1       	2026-11-15 12:49:09.761649174 +0000 UTC	deployed	istiod-1.30.8	1.30.8     
```

```
istioctl --context $CTX version
istioctl --context $CTX proxy-status
```

```
client version: 1.29.9
control plane version: 1.30.8
data plane version: 1.30.8 (7 proxies)
```

```
NAME                                                    CLUSTER       ISTIOD                            VERSION     SUBSCRIBED TYPES
details-v1-7d5cdd8bdd-s28x8.default                     cluster-a     istiod-1-30-8-7c669fc9d-khb6q     1.30.8      4 (CDS,LDS,EDS,RDS)
istio-ingressgateway-6dc45f9cb7-6q2fh.istio-ingress     cluster-a     istiod-1-30-8-7c669fc9d-khb6q     1.30.8      4 (CDS,LDS,EDS,RDS)
productpage-v1-8655fcfbbb-jsmwc.default                 cluster-a     istiod-1-30-8-7c669fc9d-khb6q     1.30.8      4 (CDS,LDS,EDS,RDS)
ratings-v1-7ff65795d8-vnm27.default                     cluster-a     istiod-1-30-8-7c669fc9d-khb6q     1.30.8      4 (CDS,LDS,EDS,RDS)
reviews-v1-5d74c74476-kq89m.default                     cluster-a     istiod-1-30-8-7c669fc9d-khb6q     1.30.8      4 (CDS,LDS,EDS,RDS)
reviews-v2-77c7c6996-bgjnp.default                      cluster-a     istiod-1-30-8-7c669fc9d-khb6q     1.30.8      4 (CDS,LDS,EDS,RDS)
reviews-v3-7d8cf4ccd4-fgvqt.default                     cluster-a     istiod-1-30-8-7c669fc9d-khb6q     1.30.8      4 (CDS,LDS,EDS,RDS)
```

**What happens without the tag `default`.** In our first run we removed the old `istiod` without setting the tag. Two things broke:

```
istioctl --context $CTX proxy-status
```

```
Error: no running Istio pods in "istio-system"
```

And a new pod in a namespace with `istio-injection=enabled` started without a sidecar (`1/1` instead of `2/2`), without any error. After we set the tag, both worked again.

Look at the Services above: the Service `istiod` is gone, only `istiod-1-30-8` is left. Everything that has the name `istiod.istio-system.svc` configured must be checked before you remove the old control plane.

## Step 8: Did it cost requests?

Stop the loop in the second terminal (Ctrl+C) and count:

```
sort ~/upgrade/calls.log | uniq -c
```

```
      2 000
    180 200
```

In our lab: 182 calls, two of them without an answer (`000`, no answer within 4 seconds). Both fell into the 17 seconds in which the pods in `default` restarted. Installing the second `istiod`, moving the gateway and removing the old `istiod` cost no call. One replica of every deployment, two calls per second: this is a small test, not a proof for production load.

## The same with istioctl

This works only for an Istio that was installed with `istioctl`. For this measurement we installed Istio 1.29.9 in cluster b with `istioctl install -f istio-operator.yaml`, with the file shown on the [previous page](01-upgrade-istio-in-place.md). There the ingress gateway runs in `istio-system`.

```
export CTX=cluster-b
cd ~/upgrade
curl -6 -fsSL https://storage.googleapis.com/istio-release/releases/$NEW/istioctl-$NEW-linux-amd64.tar.gz | tar xz
./istioctl --context $CTX x precheck
```

**istio-csr.** The same command as in step 3, for cluster b.

**Install the second control plane.** `istioctl install` with `--set revision`, with the `istioctl` of the new version and the same file as the installation:

```
./istioctl --context $CTX install --set revision=$REV -f istio-operator.yaml -y
kubectl --context $CTX -n istio-system get pods,svc -L istio.io/rev
```

```
- Processing resources for Istio core.
✔ Istio core installed ⛵️
- Processing resources for Istiod.
- Processing resources for Istiod. Waiting for Deployment/istio-system/istiod-1-30-8
✔ Istiod installed 🧠
- Processing resources for Ingress gateways.
- Processing resources for Ingress gateways. Waiting for Deployment/istio-system/istio-ingressgat...
✔ Ingress gateways installed 🛬
- Pruning removed resources
✔ Installation complete
```

```
NAME                                        READY   STATUS        RESTARTS   AGE   REV
pod/istio-ingressgateway-68d5c97887-rmlr5   1/1     Running       0          4s    1-30-8
pod/istio-ingressgateway-859454d45b-s4zsl   1/1     Terminating   0          60s   default
pod/istiod-1-30-8-58fdc64cfd-vh9m6          1/1     Running       0          6s    1-30-8
pod/istiod-688cd9b6f-cgr6h                  1/1     Running       0          62s   default

NAME                                  TYPE           CLUSTER-IP           EXTERNAL-IP               PORT(S)                                      AGE     REV
service/istio-ingressgateway          LoadBalancer   fd00:10:96::e:6b59   2a01:4f8:c016:2c9c::2:1   15021:30475/TCP,80:31582/TCP,443:31819/TCP   4m38s   1-30-8
service/istiod                        ClusterIP      fd00:10:96::9:a6c0   <none>                    15010/TCP,15012/TCP,443/TCP,15014/TCP        4m41s   default
service/istiod-1-30-8                 ClusterIP      fd00:10:96::c:7e94   <none>                    15010/TCP,15012/TCP,443/TCP,15014/TCP        7s      1-30-8
service/istiod-revision-tag-default   ClusterIP      fd00:10:96::2:5b96   <none>                    15010/TCP,15012/TCP,443/TCP,15014/TCP        4m1s    default
```

In our lab this took 9 seconds. **Different from Helm: the gateway is not a canary.** It is in the same file, so the command replaced it right away with a gateway of the new revision. If the gateway should stay on the old version for now, it must not be part of this file.

**Move the namespace.** The same as in step 5:

```
kubectl --context $CTX label namespace default istio-injection- istio.io/rev=$REV
kubectl --context $CTX rollout restart deploy -n default
kubectl --context $CTX rollout status deploy/productpage-v1
./istioctl --context $CTX proxy-status --revision $REV
```

```
NAME                                                   CLUSTER       ISTIOD                             VERSION     SUBSCRIBED TYPES
details-v1-d8849cbd6-mlqpq.default                     cluster-b     istiod-1-30-8-58fdc64cfd-vh9m6     1.30.8      4 (CDS,LDS,EDS,RDS)
istio-ingressgateway-68d5c97887-rmlr5.istio-system     cluster-b     istiod-1-30-8-58fdc64cfd-vh9m6     1.30.8      4 (CDS,LDS,EDS,RDS)
productpage-v1-75b756f86d-x6g6p.default                cluster-b     istiod-1-30-8-58fdc64cfd-vh9m6     1.30.8      4 (CDS,LDS,EDS,RDS)
ratings-v1-6c79f46f4-gkwqh.default                     cluster-b     istiod-1-30-8-58fdc64cfd-vh9m6     1.30.8      4 (CDS,LDS,EDS,RDS)
reviews-v1-5d95dd7fd6-r2qnl.default                    cluster-b     istiod-1-30-8-58fdc64cfd-vh9m6     1.30.8      4 (CDS,LDS,EDS,RDS)
reviews-v2-6dfdb476db-jvswb.default                    cluster-b     istiod-1-30-8-58fdc64cfd-vh9m6     1.30.8      4 (CDS,LDS,EDS,RDS)
reviews-v3-67b7644b78-hf46n.default                    cluster-b     istiod-1-30-8-58fdc64cfd-vh9m6     1.30.8      4 (CDS,LDS,EDS,RDS)
```

**Make the new revision the default and remove the old control plane.** The tag is one command here:

```
./istioctl --context $CTX tag set default --revision $REV --overwrite
./istioctl --context $CTX uninstall --revision default -y
./istioctl --context $CTX tag list
./istioctl --context $CTX version
```

```
Revision tag "default" created, referencing control plane revision "1-30-8". To enable injection using this
revision tag, use 'kubectl label namespace <NAMESPACE> istio.io/rev=default'
```

```
TAG     REVISION NAMESPACES
default 1-30-8   
```

```
client version: 1.30.8
control plane version: 1.30.8
data plane version: 1.30.8 (7 proxies)
```

Before it removed anything, `istioctl uninstall` printed "There are still 7 proxies pointing to the control plane revision default" and listed all seven proxies, although `proxy-status` showed them on the new `istiod`. We did not find out why. After the uninstall all seven were still connected, and a new pod in a namespace with `istio-injection=enabled` got its sidecar (`2/2`).

**Did it cost requests?**

```
    187 200
```

187 calls, all `200`.

## Helm or istioctl: what is different

| | Helm | istioctl |
|---|---|---|
| Second control plane | `helm install istiod-$REV ... --set revision=$REV` (a second release) | `istioctl install --set revision=$REV -f ...` |
| Custom resource definitions | own step (`istio-base`) | part of `istioctl install` |
| Gateway | own step, when you decide (`--set revision=$REV`) | replaced at once, if it is in the same file |
| Tag `default` | `helm template ... -s templates/revision-tags-mwc.yaml` and `kubectl apply` | `istioctl tag set default --revision $REV --overwrite` |
| Remove the old control plane | `helm delete istiod`, then `istio-base` with `defaultRevision` | `istioctl uninstall --revision default` |
| Move a namespace | label and restart | label and restart |

## What we measured

| Run | Calls | Failed | When |
|---|---|---|---|
| Helm, first run (without step 3 at first) | 574 | 1 | while the pods in `default` restarted |
| Helm, second run (the steps above) | 182 | 2 | while the pods in `default` restarted |
| istioctl | 187 | 0 | |

## What to take away

* **Nothing moves by itself.** A second `istiod` is only an offer. A workload moves when its namespace has the label `istio.io/rev` and its pod is created again.
* **Every failed call fell into the restart of the pods,** not into a step at the control plane. With one replica per deployment a restart is a short gap. This is the same for an in-place upgrade.
* **`istioctl proxy-status` needs `--revision`** as long as two control planes run. Without it you see only the proxies of the default control plane.
* **Set the tag `default` before you remove the old control plane.** Without it, namespaces with `istio-injection=enabled` silently get no sidecar any more.
* **With cert-manager and istio-csr the revision must be known to istio-csr** (`app.istio.revisions`), before the first pod is moved.
* **The Service `istiod` goes away with the old control plane** (Helm). A VM has `istiod.istio-system.svc` in its configuration. We did not test what happens to a VM, and we did not test revisions in a mesh of two clusters.

Previous: [Upgrade Istio in place](01-upgrade-istio-in-place.md)
