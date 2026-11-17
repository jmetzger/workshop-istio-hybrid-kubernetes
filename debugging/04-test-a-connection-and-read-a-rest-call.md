# Test a connection between two pods, and read a hidden REST call

## What we do

Two pods talk to each other: `shop` calls the REST API of `orders` every five seconds. You do not know what it sends. First you **test the connection** (does the call get through at all?), then you **look into the communication** and read the call: path, header and JSON body. Measured in our lab (Istio 1.29.9, IPv6 only).

| Part | What it is |
|---|---|
| `orders` | A small REST API (Deployment and Service, port `8080`) |
| `shop` | The caller. It sends one `POST` to `orders` every five seconds |
| `client` | A plain test pod with `curl`, for your own calls |

| Step | Question | Tool |
|---|---|---|
| 2 | Does the connection work? | `curl`, EndpointSlice, `istioctl proxy-config endpoints` |
| 3 | What does the node see? | `tcpdump` on the worker node |
| 4 | What does the access log show? | `Telemetry` API, log of the sidecar |
| 5 | What does the caller really send? | `tcpdump` inside the pod of `shop` |
| 6 | What does the server receive? | `tcpdump` inside the pod of `orders` |

All commands run on your bastion host as your lab user, in cluster a.

## Step 1: Start the mystery shop

Create the file `orders-and-shop.yml`. **Do not read the `shop` part closely**: the point of the exercise is that you find out what it sends without looking into the file.

<details>
<summary>orders-and-shop.yml</summary>

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: orders-code
data:
  server.py: |
    import json, socket
    from http.server import BaseHTTPRequestHandler, HTTPServer
    class H(BaseHTTPRequestHandler):
        def do_POST(self):
            n = int(self.headers.get("Content-Length", 0))
            self.rfile.read(n)
            body = json.dumps({"status": "accepted", "orderId": 4711}).encode()
            self.send_response(201)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        def do_GET(self):
            self.send_response(200); self.send_header("Content-Length", "2"); self.end_headers(); self.wfile.write(b"ok")
        def log_message(self, *a): pass
    class S(HTTPServer):
        address_family = socket.AF_INET6
    S(("::", 8080), H).serve_forever()
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orders
spec:
  replicas: 1
  selector:
    matchLabels:
      app: orders
  template:
    metadata:
      labels:
        app: orders
    spec:
      containers:
        - name: orders
          image: python:3.13-alpine
          command: ["python", "/code/server.py"]
          ports:
            - containerPort: 8080
          volumeMounts:
            - name: code
              mountPath: /code
      volumes:
        - name: code
          configMap:
            name: orders-code
---
apiVersion: v1
kind: Service
metadata:
  name: orders
spec:
  selector:
    app: orders
  ports:
    - name: http
      port: 8080
      targetPort: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop
spec:
  replicas: 1
  selector:
    matchLabels:
      app: shop
  template:
    metadata:
      labels:
        app: shop
    spec:
      containers:
        - name: shop
          image: curlimages/curl:8.11.1
          command:
            - sh
            - -c
            - |
              while true; do
                curl -s -o /dev/null -X POST http://orders:8080/api/v1/orders \
                  -H "Content-Type: application/json" \
                  -H "X-Api-Key: k-7f3a9c21" \
                  -d '{"item":"espresso-machine","quantity":2,"coupon":"SPRING-25"}'
                sleep 5
              done
```

</details>

```
kubectl apply -f orders-and-shop.yml
kubectl rollout status deploy/orders
kubectl rollout status deploy/shop
```

Start the test pod:

```
kubectl run client --image=curlimages/curl:8.11.1 -- sleep infinity
kubectl wait --for=condition=Ready pod/client
```

All three pods show `2/2` (application and sidecar):

```
kubectl get pods
```

```
NAME                              READY   STATUS    RESTARTS   AGE
client                            2/2     Running   0          3m31s
details-v1-8445d9f444-8wgtz       2/2     Running   0          4h57m
orders-6bd5c9f486-fsnms           2/2     Running   0          3m36s
productpage-v1-55678c7f78-js2nf   2/2     Running   0          4h57m
ratings-v1-755674fd5b-6ksqq       2/2     Running   0          4h57m
reviews-v1-64546cb656-p5lnv       2/2     Running   0          4h57m
reviews-v2-7ffdf844b8-zqgtd       2/2     Running   0          4h57m
reviews-v3-578c68c768-jfnpw       2/2     Running   0          4h57m
shop-7b4d459645-kkmc4             2/2     Running   0          5m59s
```

## Step 2: Test the connection

From `client` to `orders`:

```
kubectl exec client -c client -- curl -s -o /dev/null -w "HTTP %{http_code}\n" http://orders:8080/
```

```
HTTP 200
```

`HTTP 200`: name resolved, connection made, the application answered. Now a port the service does not have:

```
kubectl exec client -c client -- curl -s -o /dev/null -m 5 -w "HTTP %{http_code}\n" http://orders:9999/
```

```
HTTP 000
command terminated with exit code 28
```

No answer within five seconds: `HTTP 000` and curl exit code `28` (timeout). This is how a wrong port looks. Where to look when a connection fails:

| Question | Command |
|---|---|
| Does the service have an endpoint (a pod behind it)? | `kubectl get endpointslices -l kubernetes.io/service-name=orders` |
| Does the sidecar of the caller know that endpoint? | `istioctl proxy-config endpoints client --cluster "outbound\|8080\|\|orders.default.svc.cluster.local"` |

```
kubectl get endpointslices -l kubernetes.io/service-name=orders
```

```
NAME           ADDRESSTYPE   PORTS   ENDPOINTS                    AGE
orders-8mfzv   IPv6          8080    2a01:4f8:c016:f901::1:bb65   6m5s
```

```
istioctl proxy-config endpoints client --cluster "outbound|8080||orders.default.svc.cluster.local"
```

```
ENDPOINT                            STATUS      OUTLIER CHECK     CLUSTER
2a01:4f8:c016:f901::1:bb65:8080     HEALTHY     OK                outbound|8080||orders.default.svc.cluster.local
```

The same address twice: the pod of `orders` is known to Kubernetes and to the sidecar of the caller, and it is `HEALTHY`. The connection works.

## Step 3: Look at the wire: tcpdump on the node

Which pod of `orders` and which node? The pod address, then `tcpdump` on the worker for one packet of port `8080`:

```
O=$(kubectl get pod -l app=orders -o jsonpath='{.items[0].status.podIP}'); echo $O
ssh a-w1 "timeout 10 tcpdump -ni any -c 1 -A host $O and tcp port 8080" | cut -c1-100
```

```
2a01:4f8:c016:f901::1:bb65
10:06:08.606521 calia06ecea2836 In  IP6 2a01:4f8:c016:f901::1:bb61.59158 > 2a01:4f8:c016:f901::1:bb6
`......@*..............a*..............e....W..0U..C....J......
....MS............0......iJ.....&...j{...c..P......u.BF...!...B......?.k%~.Q..~.......:..d3.R...mdZ.
1 packet captured
7 packets received by filter
```

(The `tcpdump:` lines at the top are left out.) You see who talks to whom, and nothing else: the content is encrypted (mTLS between the two sidecars). On the wire the hidden call cannot be read.

## Step 4: The access log shows the path, not the content

Switch on the access log for the namespace (the `Telemetry` API, same as in [See the traffic](03-access-logs-instead-of-tcpdump.md)):

```
kubectl apply -f - <<EOF
apiVersion: telemetry.istio.io/v1
kind: Telemetry
metadata:
  name: access-log
  namespace: default
spec:
  accessLogging:
    - providers:
        - name: envoy
EOF
```

Wait about 15 seconds (the setting needs a moment to reach the sidecars), then read the last line of the sidecar of `shop`:

```
kubectl logs deploy/shop -c istio-proxy --tail=1
```

```
[2026-11-17T10:06:23.666Z] "POST /api/v1/orders HTTP/1.1" 201 - via_upstream - "-" 61 39 2 1 "-" "curl/8.11.1" "2dffd213-67c0-4dad-bd0e-d7e7e0b0f7e2" "orders:8080" "[2a01:4f8:c016:f901::1:bb65]:8080" outbound|8080||orders.default.svc.cluster.local [2a01:4f8:c016:f901::1:bb61]:59438 [fd00:10:96::3c31]:8080 [2a01:4f8:c016:f901::1:bb61]:53952 - default
```

First result: `shop` sends a `POST` to `/api/v1/orders`, the answer is `201`, the request body has `61` bytes, the answer `39`. That is already a lot. But the **header** and the **JSON body** are not in the access log.

## Step 5: Read the call inside the pod of `shop`

The traffic between the application and its own sidecar is plain text, because it never leaves the pod. To see it you start a **debug container** in the pod of `shop`. It shares the network of the pod, so `tcpdump` there sees everything the application sends. The application sends its call to the sidecar on port `15001` (loopback, `lo`).

```
kubectl debug -q -it $(kubectl get pod -l app=shop -o name) --image=nicolaka/netshoot --target=shop --profile=netadmin -- sh -c "timeout 8 tcpdump -ni lo -A -s0 -l 'tcp port 15001' | grep -a -E 'POST|Host:|Api-Key|^\{'"
```

```
.L..1Eo.POST /api/v1/orders HTTP/1.1
Host: orders:8080
X-Api-Key: k-7f3a9c21
{"item":"espresso-machine","quantity":2,"coupon":"SPRING-25"}
.L.K1E.yPOST /api/v1/orders HTTP/1.1
Host: orders:8080
X-Api-Key: k-7f3a9c21
{"item":"espresso-machine","quantity":2,"coupon":"SPRING-25"}
12 packets captured
24 packets received by filter
0 packets dropped by kernel
```

There it is: the hidden call, with its **API key** in a header and the **JSON body**. Two calls in eight seconds: the shop sends every five seconds. (The strange characters before `POST` are binary packet data in front of the text.)

What the command does: `kubectl debug` adds a container (image `nicolaka/netshoot`, it has `tcpdump`) to the running pod, `--target=shop` puts it next to the container `shop`, `grep` keeps only the lines we want to read. The pod is not restarted. The debug container stays in the pod until the pod is deleted.

## Step 6: What the server receives

The same on the receiving side, in the pod of `orders`. The sidecar decrypts the call and hands it to the application on port `8080` (loopback again):

```
kubectl debug -q -it $(kubectl get pod -l app=orders -o name) --image=nicolaka/netshoot --target=orders --profile=netadmin -- sh -c "timeout 8 tcpdump -ni lo -A -s0 -l 'tcp port 8080' | grep -a -i -E 'POST|Host:|Api-Key|^\{|accepted'"
```

```
10:07:08.820020 IP6 ::6.33163 > 2a01:4f8:c016:f901::1:bb65.8080: Flags [P.], seq 1:535, ack 1, win 512, options [nop,nop
jDZ..~s.POST /api/v1/orders HTTP/1.1
host: orders:8080
x-api-key: k-7f3a9c21
{"item":"espresso-machine","quantity":2,"coupon":"SPRING-25"}
.~s.jDZ.{"status": "accepted", "orderId": 4711}
12 packets captured
24 packets received by filter
0 packets dropped by kernel
```

Two things to see:

* The call is the same, and now the **answer** is visible too: `{"status": "accepted", "orderId": 4711}`.
* The caller address is `::6`, not the address of `shop`: the call comes from the sidecar of `orders`, not from `shop` directly. Header names are written in lower case (`x-api-key`): the sidecar rewrote the call.

## What we learned

| Where | What you see | Use it for |
|---|---|---|
| Node, `tcpdump` | addresses and ports, content encrypted | do packets arrive at all? |
| Access log (sidecar) | method, path, status, sizes, time, request ID | which request, did it work, how long? |
| `tcpdump` in the pod (debug container) | the full call: header, body, answer | what exactly is sent? |

The mesh encrypts the wire between the pods. Everyone who may start a debug container in a pod (`kubectl debug`) can read all calls of that pod in plain text, including keys in headers. Keep this in mind when you give out access to a cluster.

## Clean up

```
kubectl delete telemetry access-log
kubectl delete pod client
kubectl delete -f orders-and-shop.yml
```

Previous: [See the traffic: access logs instead of tcpdump](03-access-logs-instead-of-tcpdump.md)
