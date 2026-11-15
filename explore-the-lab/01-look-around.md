# Look around the lab

## What we do

Your lab already has Istio installed in sidecar mode. Nothing is left for you to install. In this exercise you look at what is running, and you learn the one command you will use all week: `istioctl proxy-status`.

Your lab consists of:

| Part | What it is |
|---|---|
| Two Kubernetes clusters, `cluster-a` and `cluster-b` | each with one control-plane node and one worker node, IPv6 only |
| Istio | control plane `istiod` in the namespace `istio-system` of each cluster, sidecar mode |
| Bookinfo | the sample application, in the namespace `default` of each cluster, every pod with a sidecar |
| Two virtual machines, `a-vm1` and `b-vm1` | plain Ubuntu, not part of the mesh yet. You add one on day 2 |

The file `~/server-overview.md` on your bastion host lists all servers, addresses and contexts of your lab.

All commands below run on your bastion host as your lab user. The default context is `cluster-a`.

## Step 1: Look at the nodes

```
kubectl get nodes -o wide
```

```
NAME           STATUS   ROLES           AGE     VERSION    INTERNAL-IP             EXTERNAL-IP 
v6-tln4-a-cp   Ready    control-plane   5m19s   v1.35.10   2a01:4f8:c016:7a12::1   <none>      
v6-tln4-a-w1   Ready    <none>          4m57s   v1.35.10   2a01:4f8:c016:4db6::1   <none>      
```

(Names and addresses differ in your lab, the output is cut on the right.) The node addresses are IPv6 addresses. Kubernetes knows no IPv4 address in this cluster.

`EXTERNAL-IP` is empty because these clusters run without a cloud controller manager, and only a cloud controller manager sets the external address of a node. The public IPv6 address of each node shows up as `INTERNAL-IP`. This is normal for a cluster built with kubeadm and is not an error.

## Step 2: Look at the pods in the mesh

```
kubectl get pods -o wide
```

```
NAME                              READY   STATUS    RESTARTS   AGE   IP                           NODE        
details-v1-6cc9f5cc44-6qf76       2/2     Running   0          93s   2a01:4f8:c016:4db6::1:c60a   v6-tln4-a-w1
productpage-v1-7f885b46fc-nmwps   2/2     Running   0          93s   2a01:4f8:c016:4db6::1:c60f   v6-tln4-a-w1
ratings-v1-77b8b6df5b-zph29       2/2     Running   0          93s   2a01:4f8:c016:4db6::1:c60b   v6-tln4-a-w1
reviews-v1-fdbf79cd8-9zv55        2/2     Running   0          93s   2a01:4f8:c016:4db6::1:c60e   v6-tln4-a-w1
reviews-v2-674c6d8b4-rcfxg        2/2     Running   0          93s   2a01:4f8:c016:4db6::1:c60c   v6-tln4-a-w1
reviews-v3-7b775c7568-h9q2w       2/2     Running   0          93s   2a01:4f8:c016:4db6::1:c60d   v6-tln4-a-w1
```

Every pod shows `2/2`, although each pod has only one application container. The second container is the Istio sidecar (Envoy). Each pod has its own IPv6 address from the network of its node, there is no NAT between pods.

## Step 3: Find the sidecar

```
kubectl get pod -l app=productpage -o jsonpath='{.items[0].spec.containers[*].name}'; ech
```

```
# Output 
# productpage
```

The sidecar is not in this list. In this lab (Kubernetes 1.35) Istio runs the sidecar as a native sidecar: a container in `initContainers` that has `restartPolicy: Always`.

```
kubectl get pod -l app=productpage -o jsonpath='{.items[0].spec.initContainers[*].name}'; echo
```

```
# Output pro
# istio-init istio-proxy
```

`istio-init` sets up the traffic redirection and ends. `istio-proxy` is the sidecar and keeps running.

## Step 4: Ask Istio who is connected

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

This is the list of all proxies that are currently connected to `istiod`: the six pods of Bookinfo and the ingress gateway.

Read it column by column:

| Column | Meaning |
|---|---|
| NAME | the proxy: pod name (or VM name) and namespace |
| CLUSTER | the cluster it belongs to |
| ISTIOD | the `istiod` pod that serves it |
| VERSION | the proxy version, after an upgrade you see here who is still old |
| SUBSCRIBED TYPES | which configuration `istiod` pushes to it (see below) |

The abbreviations are the kinds of configuration Envoy receives from `istiod`:

| Abbreviation | Meaning |
|---|---|
| CDS | clusters: where can this proxy send traffic |
| LDS | listeners: on which ports does it listen |
| EDS | endpoints: which addresses are behind a service |
| RDS | routes: how are requests distributed |
| NDS | name table: used by the DNS proxy, for example on a VM (you see it on day 2) |

> **Info: how the list is made.** `istioctl` does not ask the proxies, it asks the debug interface of `istiod`. `istiod` records every open xDS connection and, for each proxy, which configuration it sent last (with a nonce) and whether the proxy confirmed it (ACK). A proxy that is not in the list is not connected. A line in the list does not mean the proxy is healthy or its configuration is correct.

## Step 5: The same in cluster b

```
kubectl --context cluster-b get pods
istioctl --context cluster-b proxy-status
```

The same picture: its own `istiod`, its own Bookinfo. The column `CLUSTER` says `cluster-b`.

## Step 6: Watch a proxy appear and disappear

Start a new pod in the namespace `default` (it has sidecar injection):

```
kubectl run extra --image=nginx:1.27
kubectl wait --for=condition=Ready pod/extra --timeout=120s
istioctl proxy-status | grep -E "NAME|extra"
```

```
NAME                                                    CLUSTER       ISTIOD                      VERSION     SUBSCRIBED TYPES
extra.default                                           cluster-a     istiod-66dbd576c8-k4456     1.29.9      4 (CDS,LDS,EDS,RDS)
```

Now start a pod in a namespace without sidecar injection and compare:

```
kubectl create namespace plain
kubectl run plain-web -n plain --image=nginx:1.27
kubectl wait -n plain --for=condition=Ready pod/plain-web --timeout=120s
kubectl get pod plain-web -n plain
istioctl proxy-status | grep -c plain
```

```
NAME        READY   STATUS    RESTARTS   AGE
plain-web   1/1     Running   0          1s
0
```

The pod shows `1/1` and does not appear in `proxy-status`. It is not part of the mesh.

**Take-away:** `proxy-status` shows who is connected to `istiod`. It does not show whether everything works. Later in the training you will use this list to find a VM that dropped out of the mesh.

## Clean up

```
kubectl delete pod extra
kubectl delete namespace plain
```

## Summary

| Question | Command |
|---|---|
| Which proxies are connected to istiod? | `istioctl proxy-status` |
| Is this pod in the mesh? | `READY 2/2` and the pod is in `proxy-status` |
| Where is the sidecar container? | `initContainers`, name `istio-proxy` |

Next: [How Istio is installed in the lab](02-how-istio-is-installed.md)
