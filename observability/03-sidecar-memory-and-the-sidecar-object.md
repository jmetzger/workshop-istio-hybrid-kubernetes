# Memory of the sidecars: many services, and the Sidecar object

Theory for this exercise: [What Istio costs](00-what-istio-costs.md).

## What we do

You make the mesh bigger by 500 services and watch the memory of every sidecar grow, although no pod calls these services. Then you tell the sidecars in `default` that they only need their own namespace (object `Sidecar`), and the memory goes back down. Measured in our lab (Istio 1.29.9, IPv6 only, 7 sidecars).

1. Note the memory of the sidecars now
2. Create 500 services in a new namespace
3. Measure again
4. Limit what the sidecars see (`Sidecar` object)
5. Restart the pods and measure again

## Before you start

* Prometheus and the pod `client` from [Prometheus, Grafana, Kiali, and what Istio costs](01-prometheus-grafana-kiali.md) are running.
* All commands run on your bastion host as your lab user, in cluster a.
* The helper `Q` from that page, once per shell:

```
Q() { kubectl exec deploy/client -c curl -- curl -s -G "http://prometheus.istio-system:9090/api/v1/query" --data-urlencode "query=$1" | jq -r '.data.result[] | [(.metric | to_entries | map(.value) | join(" ")), .value[1]] | @tsv'; }
```

## The steps

### Step 1: Where we start

Memory of every sidecar in MiB:

```
Q 'round(sum by (pod) (container_memory_working_set_bytes{container="istio-proxy", namespace="default"}) / 1024 / 1024, 0.1)'
```

```
ratings-v1-7dd94c56db-cfk9b	30.1
reviews-v1-6c76dfd578-j2s4b	30.5
reviews-v3-796fc775f8-df8r8	30.4
client-6bd488585d-zdbbq	30.5
details-v1-5cbfd554b6-8btnb	29.2
reviews-v2-f5bf49d78-7spws	30.7
productpage-v1-6b66b4d5b-qmtdm	30.7
```

How many destinations (Envoy calls them clusters) does the sidecar of `productpage` know? One line of the output is the header.

```
istioctl proxy-config clusters deploy/productpage-v1 | wc -l
```

```
29
```

And what does Envoy itself say, in bytes?

```
kubectl exec deploy/productpage-v1 -c istio-proxy -- pilot-agent request GET 'stats?filter=server.memory_allocated'
```

```
server.memory_allocated: 8496040
```

### Step 2: Create 500 services

A namespace without sidecar injection, two small pods, and 500 services that all point to these two pods:

```
kubectl create namespace load
kubectl -n load create deploy backend --image=registry.k8s.io/pause:3.10 --replicas=2
```

```
for i in $(seq 1 500); do cat <<EOF
apiVersion: v1
kind: Service
metadata:
  name: svc-$i
  namespace: load
spec:
  selector:
    app: backend
  ports:
  - name: http
    port: 80
---
EOF
done | kubectl apply -f - | tail -1
```

```
service/svc-500 created
```

```
kubectl -n load get svc --no-headers | wc -l
```

```
500
```

### Step 3: Measure again

Wait about a minute and a half, then repeat the three commands of step 1:

```
istioctl proxy-config clusters deploy/productpage-v1 | wc -l
kubectl exec deploy/productpage-v1 -c istio-proxy -- pilot-agent request GET 'stats?filter=server.memory_allocated'
Q 'round(sum by (pod) (container_memory_working_set_bytes{container="istio-proxy", namespace="default"}) / 1024 / 1024, 0.1)'
```

```
529
server.memory_allocated: 48941648
ratings-v1-7dd94c56db-cfk9b	86
reviews-v1-6c76dfd578-j2s4b	84.7
reviews-v3-796fc775f8-df8r8	86.2
client-6bd488585d-zdbbq	84.6
details-v1-5cbfd554b6-8btnb	84.8
reviews-v2-f5bf49d78-7spws	85.7
productpage-v1-6b66b4d5b-qmtdm	86.9
```

Every sidecar went from about 30 MiB to about 85 MiB. No pod in `default` ever calls one of the new services. The sidecars hold them anyway, because by default every sidecar gets the whole mesh.

### Step 4: Limit what the sidecars see

Create the file `sidecar-default.yml`. It says: the sidecars in the namespace `default` only need the services of their own namespace (`./*`) and of `istio-system`.

```
apiVersion: networking.istio.io/v1
kind: Sidecar
metadata:
  name: default
  namespace: default
spec:
  egress:
  - hosts:
    - "./*"
    - "istio-system/*"
```

```
kubectl apply -f sidecar-default.yml
```

Wait 20 seconds, then:

```
istioctl proxy-config clusters deploy/productpage-v1 | wc -l
kubectl exec deploy/productpage-v1 -c istio-proxy -- pilot-agent request GET 'stats?filter=server.memory_allocated'
kubectl exec deploy/client -c curl -- curl -s -o /dev/null -w '%{http_code}\n' http://productpage:9080/productpage
```

```
19
server.memory_allocated: 8468104
200
```

The 500 services are gone from the sidecar (19 lines instead of 529), Envoy uses 8 MB again instead of 49 MB, and Bookinfo still answers. Now look at the memory of the containers, about a minute later:

```
Q 'round(sum by (pod) (container_memory_working_set_bytes{container="istio-proxy", namespace="default"}) / 1024 / 1024, 0.1)'
```

```
ratings-v1-7dd94c56db-cfk9b	88.3
reviews-v1-6c76dfd578-j2s4b	86.5
reviews-v3-796fc775f8-df8r8	87.6
client-6bd488585d-zdbbq	88
details-v1-5cbfd554b6-8btnb	85.1
reviews-v2-f5bf49d78-7spws	86
productpage-v1-6b66b4d5b-qmtdm	94.1
```

**Nothing changed here.** Envoy freed the memory inside, but it did not give it back to the system. Your monitoring still shows the old value.

### Step 5: Restart the pods and measure again

```
kubectl rollout restart deploy
kubectl get pods
```

Wait **five minutes**. Before that, Prometheus still lists the old pods next to the new ones. Then:

```
Q 'round(sum by (pod) (container_memory_working_set_bytes{container="istio-proxy", namespace="default"}) / 1024 / 1024, 0.1)'
```

```
ratings-v1-78ff9988b5-8gqm8	28.8
reviews-v3-6ff46d7789-5g6gg	28.9
reviews-v1-7666596cdf-gg89x	28.6
productpage-v1-7f57c5f949-br5w5	29.2
details-v1-774f44655c-dj65q	29.4
reviews-v2-5db6fc54bf-x25t2	29.2
client-747fc8df4c-xvjhx	29.7
```

About 29 MiB per sidecar, with 500 services more in the mesh than at the start.

## What to take away

| State | Clusters in the sidecar of `productpage` | Memory per sidecar |
|---|---|---|
| lab as it is | 28 | about 30 MiB |
| 500 services more | 528 | about 85 MiB |
| with the `Sidecar` object, pods not restarted | 18 | about 87 MiB |
| with the `Sidecar` object, pods restarted | 18 | about 29 MiB |

* The memory of a sidecar grows with the number of services in the mesh, here by about 0.1 MiB per service. Multiply that by the number of your pods.
* Each of the 500 services has one port and two endpoints. The sidecar holds one entry (cluster) per **port** of a service: one service with three ports added three entries in our lab. Count ports, not services.
* The `Sidecar` object takes it away again. **You only see it after the pods are restarted.**
* These are lab numbers (idle, small services with two endpoints each). Measure in your own environment with the same query.

## Clean up

```
kubectl delete -f sidecar-default.yml
kubectl delete namespace load
kubectl rollout restart deploy
```

Previous: [Make the expiry of certificates visible](02-certificate-expiry.md)
