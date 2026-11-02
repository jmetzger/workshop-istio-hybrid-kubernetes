# Look around the lab

## Background

Your lab already has Istio installed in sidecar mode. Nothing is left for you to install. In this exercise you look at what is running, and you learn the one command you will use all week: `istioctl proxy-status`.

The lab consists of:

| Part | What it is |
|---|---|
| Kubernetes cluster | one control-plane node and one worker node, IPv6 only |
| Istio | control plane `istiod` in the namespace `istio-system`, sidecar mode |
| Namespace `app` | two pods, `web` and `client`, both with a sidecar |
| Namespace `vm` | a virtual machine (`diameter-adapter`) that is part of the mesh |

All commands below run on your bastion host.

## Step 1: Look at the nodes

```
kubectl get nodes -o wide
```

Expected output (addresses differ in your lab):

```
NAME    STATUS   ROLES           AGE   VERSION    INTERNAL-IP
h6-cp   Ready    control-plane   ...   v1.35.10   2a01:4f8:c016:aa79::1
h6-w    Ready    <none>          ...   v1.35.10   2a01:4f8:c016:17b5::1
```

Note that the node addresses are IPv6 addresses. There is no IPv4 address inside the cluster.

## Step 2: Look at the pods in the mesh

```
kubectl get pods -n app -o wide
```

```
NAME     READY   STATUS    RESTARTS   AGE   IP
client   2/2     Running   0          ...   2a01:4f8:c016:aa79::1:e5c6
web      2/2     Running   0          ...   2a01:4f8:c016:aa79::1:e5c5
```

Both pods show `2/2`, although each pod has only one application container. The second container is the Istio sidecar (Envoy). Each pod has its own IPv6 address, there is no NAT between pods.

## Step 3: Find the sidecar

```
kubectl get pod web -n app -o jsonpath='{.spec.containers[*].name}'
```

```
web
```

The sidecar is not in this list. In this lab (Kubernetes 1.35) Istio runs the sidecar as a native sidecar: a container in `initContainers` that has `restartPolicy: Always`.

```
kubectl get pod web -n app -o jsonpath='{.spec.initContainers[*].name}'
```

```
istio-init istio-proxy
```

`istio-init` sets up the traffic redirection and ends. `istio-proxy` is the sidecar and keeps running.

## Step 4: Ask Istio who is connected

```
istioctl proxy-status
```

```
NAME           CLUSTER        ISTIOD                     VERSION     SUBSCRIBED TYPES
client.app     cluster-h6     istiod-8ff6d656c-v555p     1.29.9      5 (CDS,LDS,EDS,RDS,NDS)
h6-vm.vm       cluster-h6     istiod-8ff6d656c-v555p     1.29.9      5 (CDS,LDS,EDS,RDS,NDS)
web.app        cluster-h6     istiod-8ff6d656c-v555p     1.29.9      5 (CDS,LDS,EDS,RDS,NDS)
```

This is the list of all proxies that are currently connected to `istiod`. Read it column by column:

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
| NDS | name table: used by the DNS proxy, for example on the VM |

Look for the VM: `h6-vm.vm` is in the list, so the virtual machine is part of the mesh like any pod.

## Step 5: See the VM as a mesh member

```
kubectl get workloadentry -n vm
```

```
NAME                                          AGE   ADDRESS
diameter-adapter-2a01-4f8-c016-dab1--1-net1   ...   2a01:4f8:c016:dab1::1
```

A `WorkloadEntry` is how Istio describes a workload that is not a pod. This one was created automatically when the VM connected.

## Step 6: Call the VM from a pod

```
kubectl exec -n app client -c client -- curl -s http://diameter-adapter.vm.svc.cluster.local:8000/ | head -1
```

```
VM diameter-adapter (IPv6), client=::6
```

The request goes from the sidecar of `client` to the sidecar of the VM, encrypted with mutual TLS. The program on the VM answers.

## Step 7: Watch a proxy appear and disappear

Start a new pod in a namespace with sidecar injection:

```
kubectl run extra -n app --image=nginx:1.27
kubectl wait -n app --for=condition=Ready pod/extra --timeout=120s
istioctl proxy-status
```

`extra.app` is now in the list.

Now start a pod in a namespace without sidecar injection and compare:

```
kubectl create namespace plain
kubectl run plain-web -n plain --image=nginx:1.27
kubectl wait -n plain --for=condition=Ready pod/plain-web --timeout=120s
kubectl get pod plain-web -n plain
istioctl proxy-status
```

The pod shows `1/1` and does not appear in `proxy-status`. It is not part of the mesh.

**Take-away:** `proxy-status` shows who is connected to `istiod`. It does not show whether everything works. A VM can be in the list and still not receive traffic, for example if its WorkloadEntry is missing. Later in the training you will use this list to find a VM that dropped out of the mesh.

## Clean up

```
kubectl delete pod extra -n app
kubectl delete namespace plain
```

## Summary

| Question | Command |
|---|---|
| Which proxies are connected to istiod? | `istioctl proxy-status` |
| Is this pod in the mesh? | `READY 2/2` and the pod is in `proxy-status` |
| Where is the sidecar container? | `initContainers`, name `istio-proxy` |
| Which non-pod workloads exist? | `kubectl get workloadentry -A` |
