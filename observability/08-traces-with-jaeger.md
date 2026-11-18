# Traces with Jaeger: follow one request through both clusters

## What we do

Metrics tell you **that** something is slow (Prometheus, Grafana, Kiali). A trace tells you **where** the time went. One trace is the story of one request: which service called which, in which order, and how long every call took.

In this exercise you:

1. **Look at what is installed** to make the sidecars send traces.
2. **Read a trace** of Bookinfo and see that it crosses the border of the two clusters.
3. **Find a slow call** that we build in on purpose, and see what a trace shows that the graph in Kiali does not show.
4. **Lower the sampling** and see what it does to the number of traces.

Measured in our lab (Istio 1.29.9, sidecar mode, Jaeger 2.14.0 from the Istio sample add-ons, Bookinfo in the namespace `default`, both clusters connected). Everything here is **sidecar mode**: the sidecar next to the application creates the spans. There is no ztunnel and no waypoint in this lab.

The commands run on your bastion host as your lab user, in cluster a. Jaeger runs in your browser. The address and the password are in `~/monitoring-access.md` (line **Jaeger**).

## How it works

- Every sidecar (and the ingress gateway) can create a **span** for each request it handles: start time, duration, status, the names of caller and target.
- The sidecar sends its spans to a **collector**. In our lab this is `jaeger-collector` in `istio-system` of cluster a, port 4317 (OpenTelemetry protocol).
- To put the spans of one request together, all of them need the **same trace id**. The first sidecar (here: the ingress gateway) creates it and puts it into the request headers (`traceparent`, `x-b3-*`, `x-request-id`). The **application must copy these headers** from the incoming request to every outgoing request. The sidecar cannot do this for you: it does not know which outgoing call belongs to which incoming call. Bookinfo copies the headers. If your application does not, you get many short traces instead of one long one.
- Which sidecars send traces, and how many, is set by a `Telemetry` resource. Where they send them is set by an **extension provider** in the mesh configuration.

## Step 1: Create steady traffic

Open a **second terminal** on the bastion host and let this run for 5 minutes (300 calls, one per second, then it stops by itself):

```
kubectl create deploy client --image=curlimages/curl:8.11.1 --dry-run=client -o yaml -- sleep infinity | kubectl apply -f -
kubectl rollout status deploy/client
kubectl exec deploy/client -c curl -- sh -c 'for i in $(seq 1 300); do curl -s -o /dev/null http://productpage:9080/productpage; sleep 1; done'
```

(If the deployment `client` already exists, keep it.) Use the first terminal for the next steps.

## Step 2: Look at what is installed

Where do the sidecars send their traces? The extension provider is in the mesh configuration:

```
kubectl get cm istio -n istio-system -o jsonpath='{.data.mesh}' | grep -A6 extensionProviders
```

You see a provider named `jaeger`: the type is `opentelemetry`, the service is `jaeger-collector.istio-system.svc.cluster.local`, the port is `4317`.

Which sidecars use it, and how many requests are traced?

```
kubectl get telemetry -n istio-system lab-tracing -o yaml
```

The important lines are `providers: - name: jaeger` and `randomSamplingPercentage: 100`. This one `Telemetry` sits in `istio-system` (the root namespace), so it counts for the **whole mesh**. 100 percent means: every request is traced. That is right for a lab. In production it is usually 1 percent or less (step 5).

And Jaeger itself:

```
kubectl get pods,svc -n istio-system | grep -i jaeger
```

You see the pod `jaeger-...` and the services `tracing` (the web interface, port 80) and `jaeger-collector` (port 4317 and others).

Now the same service in **cluster b**. Cluster b has **no Jaeger pod**, only the service:

```
kubectl --context cluster-b get pods,svc -n istio-system | grep -i jaeger
```

(If your context has another name, use `kubectl config get-contexts`.) You see the service `jaeger-collector` and no pod. The sidecars in cluster b use this service name. Because both clusters are one mesh, the service name leads to the Jaeger pod in cluster a. Check it:

```
istioctl --context cluster-b proxy-config endpoints deploy/productpage-v1 --cluster "outbound|4317||jaeger-collector.istio-system.svc.cluster.local"
```

One endpoint, an address of cluster a. This is why the spans of **both** clusters end up in **one** Jaeger.

## Step 3: Read a trace

Open Jaeger in the browser: `https://<your jaeger address>/jaeger` (replace `<your jaeger address>` with the address from `~/monitoring-access.md`, the file already contains the full address).

1. On the left, **Service**: choose `productpage.default`. Leave the rest, click **Find Traces**.
2. The list shows your traces. Each line is one request, with the number of spans and the total duration.
3. Click one trace with **8 or 9 spans**.

You see a waterfall. For a call that went through the ingress gateway it looks like this (durations differ):

```
istio-ingressgateway   server  productpage.default ...            (whole request)
istio-ingressgateway   client  router outbound|9080||productpage...
productpage            server  productpage.default ...
productpage            client  details.default ...
details                server  details.default ...
productpage            client  reviews.default ...
reviews                server  reviews.default ...
reviews                client  ratings.default ...
ratings                server  ratings.default ...
```

How to read it:

- Every call has **two spans**: a `client` span (the sidecar of the caller, measures from its side) and a `server` span (the sidecar of the target). The difference between them is the time on the network and in the two sidecars.
- The bars are placed in time. `details` and `reviews` are called one after the other by `productpage`.
- Click a span and open **Tags**. `istio.cluster_id` tells you **in which cluster** this sidecar runs. `http.status_code`, `response_flags` and `upstream_cluster` are there too.

**Questions for your team (5 minutes):**

1. Find a trace in which `reviews` or `ratings` ran in **cluster-b** and the rest in **cluster-a**. How can you see it?
2. `reviews` has three versions. Which one answered in your trace? (Look at the tags of the `reviews` span: `istio.canonical_revision`.)
3. Which span is the longest, and is it a client or a server span?

## Step 4: Find a slow call

Somebody reports that some page loads are slow, others are fast. We build this in. A `VirtualService` delays every call from the sidecars of cluster a to `details` by 3 seconds. Save this as `01-virtualservice-details-delay.yml`:

```
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: details
spec:
  hosts:
    - details
  http:
    - fault:
        delay:
          percentage:
            value: 100
          fixedDelay: 3s
      route:
        - destination:
            host: details
```

```
kubectl apply -f 01-virtualservice-details-delay.yml
```

Wait 10 seconds. Then call the page 20 times through your ingress gateway and print the time of every call, sorted:

```
IP=$(kubectl get svc istio-ingressgateway -n istio-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
for i in $(seq 1 20); do curl -s -o /dev/null -w "%{time_total}\n" "http://[$IP]/productpage"; done | sort -n
```

Measured in our lab: 11 calls took 0.03 to 0.2 seconds, 9 calls took 3.0 to 3.2 seconds. **Some** calls are slow, **some** are fast. The pods are healthy, no errors.

Now go to Jaeger:

1. Service `productpage.default`, **Min Duration** `2s`, **Find Traces**. Only the slow requests are left.
2. Open one. The longest bar is the span `productpage` (client) to `details.default`: about **3000 ms**.
3. Look for the span of `details` itself. **There is none.** The delay is added by the sidecar of `productpage` **before** the request is sent. The request never reached `details`.
4. Open the span `productpage` (server) and check `istio.cluster_id`. In our lab all 9 slow requests ran through `productpage` in **cluster-a**, and none in cluster-b.

Why? The `VirtualService` exists only in cluster a. The sidecars of cluster b do not know it. The gateway sends a request to `productpage` in cluster a or in cluster b, so about half of the requests are slow. This is the picture of many multi-cluster problems: **the same rule has to exist in both clusters**. A graph with averages would show "a little slower". The trace shows which requests, where, and in which cluster.

Remove the rule:

```
kubectl delete virtualservice details
```

## Step 5: Lower the sampling

Tracing every request costs CPU in the sidecars and memory in Jaeger. Set the sampling to 10 percent:

```
kubectl -n istio-system patch telemetry lab-tracing --type merge -p '{"spec":{"tracing":[{"providers":[{"name":"jaeger"}],"randomSamplingPercentage":10}]}}'
```

Wait 10 seconds. Count the traces of the ingress gateway, make 100 requests, wait 15 seconds, count again. The count asks the Jaeger API from the pod `client` (inside the cluster):

```
count() { kubectl exec deploy/client -c curl -- curl -s "http://tracing.istio-system/jaeger/api/traces?service=istio-ingressgateway.istio-ingress&limit=1000&lookback=1h" | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["data"]))'; }
count
for i in $(seq 1 100); do curl -s -o /dev/null "http://[$IP]/productpage"; done
sleep 15
count
```

Measured: the count went up by 14 for 100 requests (10 percent, as set, with the usual variation).

Two things to remember:

- The **gateway decides** at the start of a request. A request that is traced at the gateway is traced in all following sidecars. Without the gateway (a call from `client` to `productpage`), the sidecar of `client` decides.
- With a low sampling, a rare error is **not** in Jaeger by chance. For errors use the metrics (Kiali, Grafana) to find the time and the service, and then look at the traces of this time.

Set the sampling back to 100 percent:

```
kubectl -n istio-system patch telemetry lab-tracing --type merge -p '{"spec":{"tracing":[{"providers":[{"name":"jaeger"}],"randomSamplingPercentage":100}]}}'
```

## What to take with you

- A trace needs **three things**: sidecars that create spans (a `Telemetry` resource), a place to send them (an extension provider in the mesh configuration), and an application that **copies the trace headers**.
- In a multi-cluster mesh the sidecars of the second cluster need the collector service name. The service can exist **without pods** in cluster b.
- Jaeger in this lab keeps the traces **in memory**. A restart of the pod deletes them. For production use a storage (Elasticsearch, Cassandra or OpenSearch) or a hosted service.
- A fault injected by a sidecar (delay, abort) shows in the trace as a **client span without a server span**.
- Compare with the other tools: Kiali shows **who calls whom** (graph), Prometheus and Grafana show **how often and how fast on average**, Jaeger shows **what happened to one request**.
