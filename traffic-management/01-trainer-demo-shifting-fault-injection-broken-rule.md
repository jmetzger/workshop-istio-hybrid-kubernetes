# Trainer demo: traffic shifting, fault injection, and a broken rule

The trainer shows this, you watch. All commands are here so that you can repeat them later. Theory: [The four objects](00-the-objects-and-why-they-matter-for-debugging.md).

Measured in our lab (Istio 1.29.9, Bookinfo in the namespace `default`, both clusters connected). The caller is the test pod `client` (a pod with a sidecar and `curl`):

```
kubectl create deploy client --image=curlimages/curl:8.11.1 -- sleep infinity
kubectl rollout status deploy/client
mkdir -p ~/traffic-demo && cd ~/traffic-demo
```

## Before: the default

Twenty calls to `reviews`. The answer names the pod that answered:

```
kubectl exec deploy/client -c curl -- sh -c 'for i in $(seq 1 20); do curl -s http://reviews:9080/reviews/0; echo; done' | grep -o "reviews-v[123]" | sort | uniq -c
```

```
      6 reviews-v1
      8 reviews-v2
      6 reviews-v3
```

Without any rule the calls are spread over all pods of the service.

## Demo 1: traffic shifting

The `DestinationRule` gives names to groups of pods (subsets). The `VirtualService` sends everything to the subset `v1`.

`01-destinationrule-reviews.yml`:

```
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: reviews
spec:
  host: reviews
  subsets:
    - name: v1
      labels:
        version: v1
    - name: v3
      labels:
        version: v3
```

`02-virtualservice-reviews-v1.yml`:

```
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: reviews
spec:
  hosts:
    - reviews
  http:
    - route:
        - destination:
            host: reviews
            subset: v1
```

```
kubectl apply -f 01-destinationrule-reviews.yml -f 02-virtualservice-reviews-v1.yml
```

The same twenty calls:

```
kubectl exec deploy/client -c curl -- sh -c 'for i in $(seq 1 20); do curl -s http://reviews:9080/reviews/0; echo; done' | grep -o "reviews-v[123]" | sort | uniq -c
```

```
# output 
20 reviews-v1
```

Now 80 percent to `v1` and 20 percent to `v3`. `03-virtualservice-reviews-80-20.yml`:

```
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: reviews
spec:
  hosts:
    - reviews
  http:
    - route:
        - destination:
            host: reviews
            subset: v1
          weight: 80
        - destination:
            host: reviews
            subset: v3
          weight: 20
```

```
kubectl apply -f 03-virtualservice-reviews-80-20.yml
```

```
kubectl exec deploy/client -c curl -- sh -c 'for i in $(seq 1 20); do curl -s http://reviews:9080/reviews/0; echo; done' | grep -o "reviews-v[123]" | sort | uniq -c
```


```
# Output 
     16 reviews-v1
      4 reviews-v3
```

What the Envoy of the **caller** got: a route with two weighted clusters, and one cluster per subset.

```
istioctl proxy-config routes deploy/client --name 9080 -o json | jq -c '.[0].virtualHosts[] | select(.name|startswith("reviews")) | .routes[0].route.weightedClusters.clusters[] | {name,weight}'
```

```
{"name":"outbound|9080|v1|reviews.default.svc.cluster.local","weight":80}
{"name":"outbound|9080|v3|reviews.default.svc.cluster.local","weight":20}
```

```
istioctl proxy-config clusters deploy/client --fqdn reviews.default.svc.cluster.local
```

```
SERVICE FQDN                          PORT     SUBSET     DIRECTION     TYPE     DESTINATION RULE
reviews.default.svc.cluster.local     9080     -          outbound      EDS      reviews.default
reviews.default.svc.cluster.local     9080     v1         outbound      EDS      reviews.default
reviews.default.svc.cluster.local     9080     v3         outbound      EDS      reviews.default
```

**The rule exists only in cluster a.** The same twenty calls from the `client` pod of cluster b (`--context cluster-b`) still reach all three versions:

```
      8 reviews-v1
      4 reviews-v2
      8 reviews-v3
```

## Demo 2: a broken rule

The `VirtualService` sends to the subset `v1`. We delete the `DestinationRule` that defines it:

```
kubectl apply -f 02-virtualservice-reviews-v1.yml
kubectl delete destinationrule reviews
```

```
kubectl exec deploy/client -c curl -- curl -s -o /dev/null -w "HTTP %{http_code}\n" http://reviews:9080/reviews/0
```

```
HTTP 503
```

Every call fails, although all pods are healthy:

```
kubectl get pods -l app=reviews
```

```
NAME                          READY   STATUS    RESTARTS   AGE
reviews-v1-fdbf79cd8-pzg62    2/2     Running   0          77m
reviews-v2-674c6d8b4-nv6ds    2/2     Running   0          77m
reviews-v3-7b775c7568-fsrsl   2/2     Running   0          77m
```

How to find it. First the objects:

```
istioctl analyze
```

```
Error [IST0101] [cluster-default] (VirtualService default/reviews) Referenced host+subset in destinationrule not found: "reviews+v1"
Error: Analyzers found issues when analyzing namespace: default.
```

Then the Envoy of the caller. The route points to a cluster for the subset `v1`:

```
istioctl proxy-config routes deploy/client --name 9080 -o json | jq -c '.[0].virtualHosts[] | select(.name|startswith("reviews")) | .routes[0].route.cluster'
```

```
"outbound|9080|v1|reviews.default.svc.cluster.local"
```

But there is no such cluster. Only the cluster without a subset is left, and the column `DESTINATION RULE` is empty:

```
istioctl proxy-config clusters deploy/client --fqdn reviews.default.svc.cluster.local
```

```
SERVICE FQDN                          PORT     SUBSET     DIRECTION     TYPE     DESTINATION RULE
reviews.default.svc.cluster.local     9080     -          outbound      EDS      
```

A route to a cluster that does not exist: that is the `503`. Repair it and call again:

```
kubectl apply -f 01-destinationrule-reviews.yml
```

```
HTTP 200
```

## Clean up

```
kubectl delete virtualservice reviews
kubectl delete destinationrule reviews
```

## What to take away

* The objects change the Envoy of the **caller**.
* `kubectl apply` accepts a rule that points to nothing. `istioctl analyze` finds it.
* A `503` with healthy pods: look at the routes and clusters of the caller.
* A rule applied in one cluster does not act in the other one.

Previous: [The four objects](00-the-objects-and-why-they-matter-for-debugging.md)
