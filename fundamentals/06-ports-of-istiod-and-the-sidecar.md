# Ports of istiod and of the sidecar (sidecar mode)

![Ports of istiod and of the sidecar in a pod: who listens where, who connects to whom](/images/ports-sidecar-and-istiod-in-pod.svg)

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
| `15053` | `pilot-agent` | DNS proxy, only if DNS capture is switched on ([see below](#dns-capture-and-port-15053)) | yes | `[::1]`, tcp and udp, in pods that started after DNS capture was switched on. **Not listening** in `productpage-v1` | the application of the pod: its DNS requests are redirected here |
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

## DNS capture and port 15053

**What it is.** Normally an application asks the DNS of the cluster (`kube-dns`) for a name. That DNS knows the Kubernetes `Service`s, but it does not know the hosts of your own `ServiceEntry`s or services outside of Kubernetes. With **DNS capture** the sidecar answers the DNS requests itself. In the words of the Istio documentation: "all DNS requests from an application will be redirected to the sidecar". The `pilot-agent` keeps a table of names and addresses that it gets from `istiod`. "If the request can be handled by the proxy, it will directly return a response to the application". Any other name is forwarded to the DNS server from `/etc/resolv.conf`.

**What it is good for.**

* Names of a `ServiceEntry` can be resolved without an own DNS entry.
* The proxy can give an address to a `ServiceEntry` that has none (*auto allocation*, addresses from `240.240.0.0/16`).
* Services outside of Kubernetes: a virtual machine uses this to find the services of the cluster (the VM exercise switches it on).

**How to switch it on.** In sidecar mode it is **off by default**. Two ways:

* for the whole mesh: `ISTIO_META_DNS_CAPTURE: "true"` in `meshConfig.defaultConfig.proxyMetadata` (ConfigMap `istio` in `istio-system`)
* for one pod: the annotation `proxy.istio.io/config` with the same value

In ambient mode it is on by default (from Istio 1.25 on). In our lab the mesh configuration of cluster a has `ISTIO_META_DNS_CAPTURE` and `ISTIO_META_DNS_AUTO_ALLOCATE` set to `"true"`, because the VM exercise switches them on.

**When is it read?** When the pod is created. We measured it:

| Pod | Started | Listens on `15053` |
|---|---|---|
| `productpage-v1` | before DNS capture was switched on | no |
| a new test pod in a labelled namespace | after | yes: `[::1]:15053`, tcp and udp |

So after you change the setting, existing pods keep the old behaviour until they are restarted. That is why this page, measured on `productpage-v1`, shows `15053` as not listening.

## istiod in the cluster

| Port | Name in the Deployment | Task | Measured | Who connects |
|---|---|---|---|---|
| `15012` | `tls-xds` | **xDS** (the configuration for the proxies) and **CA** (certificates), with TLS and mTLS. Recommended for production | all addresses; in the `Service istiod` (named `https-dns`) | the sidecars. The `pilot-agent` opens the connection when the pod starts |
| `15010` | `grpc-xds` | xDS and CA in plain text, only for secure networks | all addresses; in the `Service istiod` | not used in our lab |
| `15014` | `http-monitoring` | Control plane monitoring: the metrics of `istiod` | all addresses; in the `Service istiod` | Prometheus |
| `15017` | `https-webhooks` | Webhooks: sidecar injection and validation. The Service port is `443`, forwarded to `15017` | all addresses; the `Service istiod` maps `443` to `15017` | the `kube-apiserver`, when a pod is created: this is the [sidecar injection](07-sidecar-injection.md) |
| `8080` | `http-debug` | Debug interface (deprecated, container port only). The readiness probe of `istiod` asks `/ready` here | all addresses; container port, not in a Service | the kubelet |
| `9876` | | not in the Istio table: the introspection interface of `istiod` (ControlZ) | `127.0.0.1` only | only inside the `istiod` pod |

The `Service istiod` (type `ClusterIP`) has the ports `15010`, `15012`, `443` and `15014`.

### What the words mean

| Word | Meaning |
|---|---|
| **xDS** | The family of discovery APIs over which `istiod` sends the configuration to the proxies: clusters, listeners, endpoints, routes and names (CDS, LDS, EDS, RDS, NDS). You see them in the column `SUBSCRIBED TYPES` of `istioctl proxy-status`. It is one long-lived gRPC connection that the proxy opens |
| **CA** | `istiod` is also the certificate authority of the mesh. The `pilot-agent` sends a certificate request with the token of the service account of the pod (the volume `istio-token`) on the same connection and gets the workload certificate that Envoy uses for mTLS |
| **`15012` and `15010`** | The same two services, once with TLS (`15012`) and once in plain text (`15010`). Plain text is only for networks you trust completely. We use `15012` |
| **Webhook** | An HTTPS address that the `kube-apiserver` calls when something is created. A *mutating* webhook may change the object (the sidecar injection), a *validating* webhook may reject it (`istiod` checks Istio resources). Both use `443` and `15017` |
| **Readiness (`8080`)** | The kubelet asks `/ready` to find out whether `istiod` is ready to work. Only then the `Service` sends traffic to it |
| **ControlZ (`9876`)** | A small introspection interface of `istiod` (log levels, internal state). It listens on `127.0.0.1` only, so it is not reachable from outside the pod. We do not use it in the course |

## Who connects to whom

1. **The sidecar starts.** The `pilot-agent` connects to `istiod` on `15012`: it gets the configuration and a certificate. The sidecar opens this connection, `istiod` never connects to the pod. (How the sidecar got into the pod in the first place: [sidecar injection](07-sidecar-injection.md).)
2. **The application calls another pod (outbound).** The application opens a connection. iptables sends it to Envoy on `15001`. Envoy sends it with mTLS to the other pod.
3. **Another pod calls the application (inbound).** The mTLS connection arrives. iptables redirects it to the Envoy on `15006`, which ends the mTLS and hands the request to the application (here `9080`).
4. **Prometheus collects metrics.** It scrapes `15020` (everything merged) or `15090` (Envoy only) of every pod, and `15014` of `istiod`.
5. **The kubelet checks the sidecar.** It asks `15021` (`/healthz/ready`) as startup and readiness probe.

## Look at it yourself

The commands run on your bastion host as your lab user. They use the `productpage` pod of Bookinfo.

```
kubectl exec deploy/productpage-v1 -c istio-proxy -- ss -ltnp
kubectl logs deploy/productpage-v1 -c istio-init | grep -E "^-A ISTIO_(INBOUND|REDIRECT|IN_REDIRECT)"
kubectl get pod -l app=productpage -o jsonpath='{.items[0].metadata.annotations}'
kubectl -n istio-system get deploy istiod -o jsonpath='{range .spec.template.spec.containers[0].ports[*]}{.name}={.containerPort} {end}'
kubectl -n istio-system get svc istiod
kubectl -n istio-system get cm istio -o jsonpath='{.data.mesh}' | grep ISTIO_META_DNS
```

The same ports on a virtual machine, and what changes there: [Ports of istiod and of the sidecar on the VM](../virtual-machines/00-ports-of-sidecar-and-istiod.md).

Previous: [Istio ingress gateway vs. Kubernetes Gateway API](05-ingress-gateway-vs-gateway-api.md)
Next: [How the sidecar gets into the pod (sidecar injection)](07-sidecar-injection.md)
