# Outage: istiod is gone

## What we do

You switch off the control plane of cluster a and look at what still works and what does not. Then you switch it on again. Measured in our lab (Istio 1.29.9, sidecar mode).

All commands run on your bastion host as your lab user, in cluster a. You need the test pod `client`:

```
kubectl create deploy client --image=curlimages/curl:8.11.1 -- sleep infinity
kubectl rollout status deploy/client
```

## Step 1: Switch off istiod

```
kubectl -n istio-system scale deploy istiod --replicas=0
```

## Step 2: Traffic still works

```
kubectl exec deploy/client -c curl -- curl -s -o /dev/null -m 5 -w "HTTP %{http_code}\n" http://details:9080/details/0
```

```
HTTP 200
```

The proxies keep the configuration they got last. `istiod` is not in the path of a request.

## Step 3: What does not work any more

**You are blind.** `istioctl` asks `istiod`:

```
istioctl proxy-status
```

```
Error: no running Istio pods in "istio-system"
```

**No new pods in a namespace with injection.** The sidecar is added by a webhook that `istiod` serves:

```
kubectl create deploy client2 --image=curlimages/curl:8.11.1 -- sleep infinity
kubectl get rs,pods -l app=client2
```

```
NAME                                 DESIRED   CURRENT   READY   AGE
replicaset.apps/client2-6d858f8c4d   1         0         0       8s
```

The deployment is created, but there is no pod. The reason is in the events of the ReplicaSet:

```
kubectl describe rs -l app=client2 | tail -3
```

```
Warning  FailedCreate  0s (x8 over 7s)  replicaset-controller  Error creating: Internal error occurred: failed calling webhook "namespace.sidecar-injector.istio.io": failed to call webhook: Post "https://istiod.istio-system.svc:443/inject?timeout=10s": dial tcp [fd00:10:96::9:5d8]:443: connect: connection refused
```

This also hits a pod that restarts or a deployment that scales up: with a dead `istiod` you lose capacity over time. `kubectl get pods` shows nothing, you must look at the ReplicaSet.

**No changes.** A new `VirtualService`, a new pod of another service, a new endpoint: the proxies do not learn about it.

| | With istiod | Without istiod |
|---|---|---|
| Calls between existing pods | work | work |
| `istioctl proxy-status` | works | error |
| New pod in a namespace with injection | gets a sidecar | is not created |
| Changes of rules and endpoints | reach the proxies | do not reach the proxies |

```
kubectl delete deploy client2
```

## Step 4: Switch istiod on again

```
kubectl -n istio-system scale deploy istiod --replicas=1
kubectl -n istio-system rollout status deploy/istiod
```

Wait a moment, then look whether the proxies are connected again:

```
istioctl proxy-status
```

Nothing had to be restarted. The proxies reconnect by themselves.

## What about the certificates?

In our lab `istiod` is not the certificate authority: a sidecar asks `istio-csr` (cert-manager) for its certificate, not `istiod`. With `istiod` as the certificate authority (the Istio default) the sidecars ask `istiod`, so an outage of `istiod` is also an outage of the certificate authority. We look at this on day 2: [Outage with a virtual machine](../virtual-machines/03-outage-what-happens-to-the-vm.md).
