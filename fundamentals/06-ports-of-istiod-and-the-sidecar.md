# Ports of istiod and of the sidecar (sidecar mode)

In sidecar mode two programs open the ports that matter in this course: **`istiod`** in the cluster and the **sidecar** in every pod of the mesh. This page lists every port, what it is for and who connects to it. The column "Measured" is what we saw in our lab (Istio 1.29.9, IPv6 only, the `productpage` pod of Bookinfo, `ss -ltnp` in the pod, `kubectl` for `istiod`). The tasks come from the Istio documentation (*Ports used by Istio*).

## Who is who

* **`istiod`** runs as a Deployment in the namespace `istio-system`. The program is called `pilot-discovery`. It gives the proxies their configuration (xDS), signs the workload certificates (it is the CA) and answers the webhooks of the `kube-apiserver`.
* **The sidecar** is the container `istio-proxy` in every pod of the mesh. It runs two programs: **`pilot-agent`** (starts Envoy, fetches the certificate from `istiod`, answers the health check) and **Envoy** (the proxy that carries the traffic).

In our lab `istio-proxy` is a Kubernetes *native sidecar*: it is listed under `initContainers` with `restartPolicy: Always`. It starts before the application and keeps running next to it. The init container `istio-init` runs first and sets the iptables rules of the pod.

## The sidecar in a pod

| Port | Program | Task | Only inside the pod | Measured in our pod | Who connects |
|---|---|---|---|---|---|
| `15001` | Envoy | **Outbound:** all outgoing TCP traffic of the application is redirected here | no | `[::]` | iptables of the pod |
| `15006` | Envoy | **Inbound:** incoming TCP traffic for the application is redirected here | no | `[::]` | iptables of the pod |
| `15000` | Envoy | Envoy admin port (commands, diagnostics) | yes | `[::1]` (loopback only) | the pod itself |
| `15020` | `pilot-agent` | Merged Prometheus metrics of the agent, Envoy and the application | no | all addresses (`*`) | Prometheus |
| `15021` | Envoy | Health checks of the sidecar (`/healthz/ready`) | no | `[::]` | the kubelet: startup and readiness probe of `istio-proxy` |
| `15090` | Envoy | Prometheus metrics of Envoy itself | no | `[::]` | Prometheus |
| `15053` | `pilot-agent` | DNS proxy, only if DNS capture is switched on | yes | **not listening** in our pod | the application of the pod (when on) |
| `9080` | the application (`productpage`) | the application itself | no | `*` | other pods (the traffic is redirected to `15006` first) |

Listed by Istio, but **not listening** in our pod: `15002` (failure detection), `15004` (debug port) and `15008` (HBONE tunnel, used in ambient mode; in sidecar mode the iptables rules leave it alone). `[::]` is the IPv6 wildcard address. In our IPv6-only cluster that means all addresses of the pod.

On the pod the annotations `prometheus.io/scrape: "true"`, `prometheus.io/port: "15020"` and `prometheus.io/path: /stats/prometheus` tell Prometheus where to scrape. Port `15020` gives everything in one place (agent, Envoy and application), `15090` only the metrics of Envoy.

### What iptables redirects

The init container `istio-init` sets these rules in the network namespace of the pod (we read them from its log):

| Direction | Rule | Meaning |
|---|---|---|
| outbound | `ISTIO_REDIRECT`: all TCP to `15001` | everything the application sends goes to Envoy first |
| inbound | `ISTIO_IN_REDIRECT`: all TCP to `15006` | everything that arrives for the application goes to Envoy first |
| inbound, **not** redirected | `15008`, `15090`, `15021`, `15020` (`RETURN`) | the ports of the sidecar itself stay reachable directly |
| outbound, **not** redirected | traffic of the proxy itself (user and group `1337`) and traffic to `127.0.0.1` | otherwise Envoy would redirect its own traffic to itself |

## istiod in the cluster

| Port | Name in the Deployment | Task | Measured | Who connects |
|---|---|---|---|---|
| `15012` | `tls-xds` | **xDS** (the configuration for the proxies) and **CA** (certificates), with TLS and mTLS. Recommended for production | all addresses; in the `Service istiod` (named `https-dns`) | the sidecars. The `pilot-agent` opens the connection when the pod starts |
| `15010` | `grpc-xds` | xDS and CA in plain text, only for secure networks | all addresses; in the `Service istiod` | not used in our lab |
| `15014` | `http-monitoring` | Control plane monitoring: the metrics of `istiod` | all addresses; in the `Service istiod` | Prometheus |
| `15017` | `https-webhooks` | Webhooks: sidecar injection and validation. The Service port is `443`, forwarded to `15017` | all addresses; the `Service istiod` maps `443` to `15017` | the `kube-apiserver` |
| `8080` | `http-debug` | Debug interface (deprecated, container port only). The readiness probe of `istiod` asks `/ready` here | all addresses; container port, not in a Service | the kubelet |
| `9876` | | not in the Istio table: the introspection interface of `istiod` (ControlZ) | `127.0.0.1` only | only inside the `istiod` pod |

The `Service istiod` (type `ClusterIP`) has the ports `15010`, `15012`, `443` and `15014`.

## Who connects to whom

1. **A pod starts.** The `kube-apiserver` calls `istiod` on `443` (forwarded to `15017`) so that the sidecar is injected. Then the `pilot-agent` connects to `istiod` on `15012`: it gets the configuration and a certificate. The sidecar opens this connection, `istiod` never connects to the pod.
2. **A pod calls another pod.** The application opens a connection. iptables sends it to Envoy on `15001`. Envoy sends it with mTLS to the other pod. There iptables redirects it to the Envoy on `15006`, which hands it to the application (here `9080`).
3. **Prometheus collects metrics.** It scrapes `15020` (everything merged) or `15090` (Envoy only) of every pod, and `15014` of `istiod`.
4. **The kubelet checks the sidecar.** It asks `15021` (`/healthz/ready`) as startup and readiness probe.

## Look at it yourself

The commands run on your bastion host as your lab user. They use the `productpage` pod of Bookinfo.

```
kubectl exec deploy/productpage-v1 -c istio-proxy -- ss -ltnp
kubectl logs deploy/productpage-v1 -c istio-init | grep -E "^-A ISTIO_(INBOUND|REDIRECT|IN_REDIRECT)"
kubectl get pod -l app=productpage -o jsonpath='{.items[0].metadata.annotations}'
kubectl -n istio-system get deploy istiod -o jsonpath='{range .spec.template.spec.containers[0].ports[*]}{.name}={.containerPort} {end}'
kubectl -n istio-system get svc istiod
```

The same ports on a virtual machine, and what changes there: [Ports of istiod and of the sidecar on the VM](../virtual-machines/00-ports-of-sidecar-and-istiod.md).

Previous: [Istio ingress gateway vs. Kubernetes Gateway API](05-ingress-gateway-vs-gateway-api.md)
