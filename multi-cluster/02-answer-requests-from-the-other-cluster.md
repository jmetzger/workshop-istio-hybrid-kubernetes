# Answer requests with pods from the other cluster

## Background

In the previous exercise you checked the link between two clusters. Now you see what the link is good for: a request that enters cluster B can be answered by pods that run in cluster A, without a gateway between the clusters. The pods talk directly over IPv6, protected by mTLS.

What makes this work:

| Part | Where to see it |
|---|---|
| Both clusters trust the same root CA | step 1 |
| Each `istiod` can read the other API server (remote secret) | `istioctl remote-clusters`, status `synced` |
| The pods of both clusters can reach each other (routed IPv6 network, same Istio `network`) | step 2 |
| The service exists in both clusters (same name, same namespace) | Bookinfo from the exercise "Expose Bookinfo through the ingress gateway over IPv6" |

Prerequisite: Bookinfo runs in **both** clusters and is published through both gateways (do the ingress gateway exercise in cluster A and in cluster B).

```
export CTX_A=<context of cluster A>
export CTX_B=<context of cluster B>
export GATEWAY_B=<external address of the ingress gateway in cluster B>
```

## Step 1: Compare the root certificates

```
for CTX in $CTX_A $CTX_B; do
  kubectl --context $CTX get cm istio-ca-root-cert -n default -o jsonpath='{.data.root-cert\.pem}' | openssl x509 -noout -fingerprint -sha256
done
```

Both lines must show the same fingerprint. If they differ, the clusters do not trust each other's certificates and cross-cluster traffic fails.

## Step 2: Look at the endpoints of `reviews`

The Envoy of `productpage` in cluster B knows all endpoints of the service `reviews`:

```
export PP_B=$(kubectl --context $CTX_B get pod -l app=productpage -o jsonpath='{.items[0].metadata.name}')
istioctl --context $CTX_B proxy-config endpoints $PP_B --cluster "outbound|9080||reviews.default.svc.cluster.local"
```

Expected output: six endpoints, three from the network of each cluster (addresses differ in your lab):

```
ENDPOINT                            STATUS      OUTLIER CHECK     CLUSTER
2a01:4f8:c016:a758::1:9110:9080     HEALTHY     OK                outbound|9080||reviews.default.svc.cluster.local
2a01:4f8:c016:a758::1:9111:9080     HEALTHY     OK                outbound|9080||reviews.default.svc.cluster.local
2a01:4f8:c016:a758::1:9112:9080     HEALTHY     OK                outbound|9080||reviews.default.svc.cluster.local
2a01:4f8:c016:aa79::1:a84e:9080     HEALTHY     OK                outbound|9080||reviews.default.svc.cluster.local
2a01:4f8:c016:aa79::1:a853:9080     HEALTHY     OK                outbound|9080||reviews.default.svc.cluster.local
2a01:4f8:c016:aa79::1:a854:9080     HEALTHY     OK                outbound|9080||reviews.default.svc.cluster.local
```

The first three belong to cluster A, the last three to cluster B. Compare with the pod addresses:

```
kubectl --context $CTX_A get pods -l app=reviews -o wide
kubectl --context $CTX_B get pods -l app=reviews -o wide
```

## Step 3: Take away the local pods

Scale `reviews` to zero in cluster B:

```
for D in reviews-v1 reviews-v2 reviews-v3; do kubectl --context $CTX_B scale deploy $D --replicas=0; done
kubectl --context $CTX_B wait --for=delete pod -l app=reviews --timeout=90s
kubectl --context $CTX_B get pods -l app=reviews
```

```
No resources found in default namespace.
```

Wait a few seconds, then look at the endpoints again:

```
istioctl --context $CTX_B proxy-config endpoints $PP_B --cluster "outbound|9080||reviews.default.svc.cluster.local"
```

Only the three endpoints of cluster A are left.

## Step 4: Call cluster B from outside

```
for i in 1 2 3 4 5 6; do
  curl -6 -s "http://[$GATEWAY_B]/productpage" | grep -c Reviewer1
done
```

```
1
1
1
1
1
1
```

Every answer contains the reviews, although cluster B has no `reviews` pod. The page of cluster B was built with pods of cluster A.

## Step 5: Repair

```
for D in reviews-v1 reviews-v2 reviews-v3; do kubectl --context $CTX_B scale deploy $D --replicas=1; done
kubectl --context $CTX_B get pods -l app=reviews
```

## Questions

* What would you see in step 2 if the remote secret of cluster B were missing in cluster A?
* The root CA must be the same in both clusters. What happens to the connection between pods of the two clusters if you replace the CA in only one cluster?
