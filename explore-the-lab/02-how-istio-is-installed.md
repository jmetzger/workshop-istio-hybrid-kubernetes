# How Istio is installed in the lab

## What we do

Istio is already installed in your lab, in both clusters. You install nothing. On this page you look at **how** it is installed, so that you know where to look when something is wrong. Everything was installed with Helm.

All commands run on your bastion host as your lab user. The default context is `cluster-a`; add `--context cluster-b` (kubectl, istioctl) or `--kube-context cluster-b` (helm) for the other cluster.

## Step 1: The Helm releases

```
helm ls -A
```

```
NAME                  	NAMESPACE     	REVISION	UPDATED                                	STATUS  	CHART                         	APP VERSION
cert-manager          	cert-manager  	1       	2026-11-13 15:42:43.178366457 +0000 UTC	deployed	cert-manager-v1.21.3          	v1.21.3    
cert-manager-istio-csr	cert-manager  	1       	2026-11-13 15:43:04.692906364 +0000 UTC	deployed	cert-manager-istio-csr-v0.19.1	v0.19.1    
istio-base            	istio-system  	1       	2026-11-13 15:44:53.304012727 +0000 UTC	deployed	base-1.29.9                   	1.29.9     
istio-ingressgateway  	istio-ingress 	1       	2026-11-13 15:45:05.901843359 +0000 UTC	deployed	gateway-1.29.9                	1.29.9     
istiod                	istio-system  	1       	2026-11-13 15:44:56.835836613 +0000 UTC	deployed	istiod-1.29.9                 	1.29.9     
metallb               	metallb-system	1       	2026-11-13 15:44:19.835960219 +0000 UTC	deployed	metallb-0.16.1                	v0.16.1    
```

| Release | What it is |
|---|---|
| `istio-base` | the custom resource definitions of Istio |
| `istiod` | the control plane |
| `istio-ingressgateway` | the ingress gateway (an Envoy without an application) |
| `cert-manager`, `cert-manager-istio-csr` | the certificate authority of the mesh (see [cert-manager with istio-csr](../fundamentals/08-certificates-with-cert-manager-and-istio-csr.md)) |
| `metallb` | gives `LoadBalancer` Services a fixed IPv6 address |

Look at the order of the times: cert-manager and istio-csr first, then Istio. `istiod` needs its certificate from cert-manager when it starts.

## Step 2: The settings of `istiod`

```
helm -n istio-system get values istiod
```

```
USER-SUPPLIED VALUES:
global:
  caAddress: cert-manager-istio-csr.cert-manager.svc:443
  meshID: mesh-tln4
  multiCluster:
    clusterName: cluster-a
  network: net1
pilot:
  env:
    ENABLE_CA_SERVER: "false"
  resources:
    requests:
      cpu: 200m
      memory: 512Mi
```

| Value | Meaning |
|---|---|
| `global.meshID` | the name of the mesh. The same in both clusters |
| `global.multiCluster.clusterName` | the name of this cluster in the mesh. Different in every cluster (`cluster-a`, `cluster-b`) |
| `global.network` | the name of the network. Both clusters have `net1`: the pods reach each other directly |
| `global.caAddress`, `ENABLE_CA_SERVER` | `istiod` is no certificate authority, the sidecars ask `istio-csr` |

Later exercises add values (for example for virtual machines). `helm get values` always shows the current state, and `helm history istiod -n istio-system` shows the changes.

## Step 3: What runs in `istio-system`

```
kubectl -n istio-system get pods,svc
```

```
NAME                          READY   STATUS    RESTARTS   AGE
pod/istiod-66dbd576c8-k4456   1/1     Running   0          2m18s

NAME             TYPE        CLUSTER-IP           EXTERNAL-IP   PORT(S)                                 AGE
service/istiod   ClusterIP   fd00:10:96::c:331a   <none>        15010/TCP,15012/TCP,443/TCP,15014/TCP   2m18s
```

One pod is the whole control plane. What the ports are for: [Ports of istiod and of the sidecar](../fundamentals/06-ports-of-istiod-and-the-sidecar.md).

The mesh configuration that `istiod` and all proxies use is in a ConfigMap:

```
kubectl -n istio-system get cm istio -o jsonpath="{.data.mesh}"
```

```
defaultConfig:
  discoveryAddress: istiod.istio-system.svc:15012
  meshId: mesh-tln4
defaultProviders:
  metrics:
  - prometheus
enablePrometheusMerge: true
rootNamespace: istio-system
trustDomain: cluster.local
```

## Step 4: The Istio APIs

```
kubectl get crd | grep istio.io | cut -d" " -f1
```

```
authorizationpolicies.security.istio.io
destinationrules.networking.istio.io
envoyfilters.networking.istio.io
gateways.networking.istio.io
peerauthentications.security.istio.io
proxyconfigs.networking.istio.io
requestauthentications.security.istio.io
serviceentries.networking.istio.io
sidecars.networking.istio.io
telemetries.telemetry.istio.io
virtualservices.networking.istio.io
wasmplugins.extensions.istio.io
workloadentries.networking.istio.io
workloadgroups.networking.istio.io
```

These fourteen are the classic Istio APIs. We use `gateways`, `virtualservices`, `destinationrules`, `serviceentries` (traffic), `peerauthentications` (mTLS) and `workloadgroups`, `workloadentries` (virtual machines).

## Step 5: Which namespaces get a sidecar

```
kubectl get ns -L istio-injection
```

```
NAME              STATUS   AGE     ISTIO-INJECTION
calico-system     Active   5m23s   
cert-manager      Active   4m32s   
default           Active   5m48s   enabled
istio-ingress     Active   2m10s   
istio-system      Active   4m33s   
kube-node-lease   Active   5m48s   
kube-public       Active   5m48s   
kube-system       Active   5m48s   
metallb-system    Active   2m55s   
tigera-operator   Active   5m43s   
```

Only `default` has the label. Bookinfo runs there, and every pod has a sidecar:

```
kubectl get pods
```

```
NAME                              READY   STATUS    RESTARTS   AGE
details-v1-6cc9f5cc44-6qf76       2/2     Running   0          2m2s
productpage-v1-7f885b46fc-nmwps   2/2     Running   0          2m2s
ratings-v1-77b8b6df5b-zph29       2/2     Running   0          2m2s
reviews-v1-fdbf79cd8-9zv55        2/2     Running   0          2m2s
reviews-v2-674c6d8b4-rcfxg        2/2     Running   0          2m2s
reviews-v3-7b775c7568-h9q2w       2/2     Running   0          2m2s
```

## Step 6: Versions, and who is connected

```
istioctl version
```

```
client version: 1.29.9
control plane version: 1.29.9
data plane version: 1.29.9 (7 proxies)
```

Three versions: `istioctl` on your bastion host, `istiod`, and the proxies. They should match.

```
istioctl proxy-status
```

```
NAME                                                    CLUSTER       ISTIOD                      VERSION     SUBSCRIBED TYPES
details-v1-6cc9f5cc44-6qf76.default                     cluster-a     istiod-66dbd576c8-k4456     1.29.9      4 (CDS,LDS,EDS,RDS)
istio-ingressgateway-5dc49cc6bf-57hqg.istio-ingress     cluster-a     istiod-66dbd576c8-k4456     1.29.9      4 (CDS,LDS,EDS,RDS)
productpage-v1-7f885b46fc-nmwps.default                 cluster-a     istiod-66dbd576c8-k4456     1.29.9      4 (CDS,LDS,EDS,RDS)
ratings-v1-77b8b6df5b-zph29.default                     cluster-a     istiod-66dbd576c8-k4456     1.29.9      4 (CDS,LDS,EDS,RDS)
reviews-v1-fdbf79cd8-9zv55.default                      cluster-a     istiod-66dbd576c8-k4456     1.29.9      4 (CDS,LDS,EDS,RDS)
reviews-v2-674c6d8b4-rcfxg.default                      cluster-a     istiod-66dbd576c8-k4456     1.29.9      4 (CDS,LDS,EDS,RDS)
reviews-v3-7b775c7568-h9q2w.default                     cluster-a     istiod-66dbd576c8-k4456     1.29.9      4 (CDS,LDS,EDS,RDS)
```

Every line is a proxy that is connected to this `istiod`. A proxy that is missing here gets no configuration. This is the command you will use most this week.

## Step 7: The same in cluster b

Repeat step 1, 2 and 6 for cluster b:

```
helm --kube-context cluster-b ls -A
helm --kube-context cluster-b -n istio-system get values istiod
istioctl --context cluster-b proxy-status
```

What is different? Only `clusterName`. Everything else is the same on purpose.

Previous: [Look around the lab](01-look-around.md)
