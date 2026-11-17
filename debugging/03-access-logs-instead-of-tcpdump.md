# See the traffic: access logs instead of tcpdump

## What we do

In a mesh `tcpdump` shows much less than you are used to: the traffic between two sidecars is encrypted. You see that with your own eyes, and then you switch on the access log of Envoy, which shows every request in plain text, on both sides. Measured in our lab (Istio 1.29.9, IPv6 only).

All commands run on your bastion host as your lab user, in cluster a. You need the test pod `client`:

```
kubectl create deploy client --image=curlimages/curl:8.11.1 -- sleep infinity
kubectl rollout status deploy/client
```

## Step 1: tcpdump sees packets, but no content

Start `tcpdump` on the worker node for six seconds, and call `details` in a second terminal while it runs:

```
ssh a-w1 "timeout 6 tcpdump -ni any -c 6 -A tcp port 9080"
```

```
kubectl exec deploy/client -c curl -- curl -s -o /dev/null http://details:9080/details/0
```

```
16:00:51.804816 calie410ea786f2 In  IP6 2a01:4f8:c016:4db6::1:c616.41934 > 2a01:4f8:c016:4db6::1:c60a.9080: Flags [.], ack 796, win 762, options [nop,nop,TS val
`.... .@*.....M.........*.....M........
..#x.\..B..............
.'A..3A.
```

You see who talks to whom (the two pod addresses) and on which port. You do not see `GET /details/0`: the content is encrypted (mTLS). `tcpdump` still answers one question well: do packets arrive at all?

## Step 2: Switch on the access log

In our lab the access log is off. The `Telemetry` API switches it on, here for one namespace. `telemetry-access-log.yml`:

```
apiVersion: telemetry.istio.io/v1
kind: Telemetry
metadata:
  name: access-log
  namespace: default
spec:
  accessLogging:
    - providers:
        - name: envoy
```

```
kubectl apply -f telemetry-access-log.yml
```

No pod has to restart.

## Step 3: One request, two log lines

```
kubectl exec deploy/client -c curl -- curl -s -o /dev/null -w "HTTP %{http_code}\n" http://details:9080/details/0
```

The sidecar of the **caller** (outbound):

```
kubectl logs deploy/client -c istio-proxy --tail=1
```

```
[2026-11-13T16:00:40.595Z] "GET /details/0 HTTP/1.1" 200 - via_upstream - "-" 0 178 7 7 "-" "curl/8.11.1" "ebf458f4-dcca-4ffe-9c47-72d01bd41645" "details:9080" "[2a01:4f8:c016:4db6::1:c60a]:9080" outbound|9080||details.default.svc.cluster.local [2a01:4f8:c016:4db6::1:c616]:41934 [fd00:10:96::2:c6c3]:9080 [2a01:4f8:c016:4db6::1:c616]:56328 - default
```

The sidecar of the **callee** (inbound):

```
kubectl logs deploy/details-v1 -c istio-proxy --tail=1
```

```
[2026-11-13T16:00:40.599Z] "GET /details/0 HTTP/1.1" 200 - via_upstream - "-" 0 178 1 1 "-" "curl/8.11.1" "ebf458f4-dcca-4ffe-9c47-72d01bd41645" "details:9080" "[2a01:4f8:c016:4db6::1:c60a]:9080" inbound|9080|| [::6]:50569 [2a01:4f8:c016:4db6::1:c60a]:9080 [2a01:4f8:c016:4db6::1:c616]:41934 outbound_.9080_._.details.default.svc.cluster.local default
```

What to read in a line (from the caller line above):

| Part | Value | Meaning |
|---|---|---|
| request | `"GET /details/0 HTTP/1.1"` | method and path, in plain text |
| response code | `200` | what the caller got |
| response flags | `-` | empty: nothing special. Here Envoy writes why a request failed |
| duration | `7` | milliseconds |
| request ID | `ebf458f4-...` | **the same in both lines.** With it you find one request in the logs of all sidecars on its way |
| upstream host | `[2a01:4f8:c016:4db6::1:c60a]:9080` | the pod that answered. In a mesh with two clusters you see here in which cluster it is |
| cluster | `outbound\|9080\|\|details.default.svc.cluster.local` | the Envoy cluster that was used (with a subset, if a `DestinationRule` has one) |

## Step 4: A request that fails

```
kubectl exec deploy/client -c curl -- curl -s -o /dev/null -w "HTTP %{http_code}\n" http://details:9080/nothing
kubectl logs deploy/client -c istio-proxy --tail=1
```

```
HTTP 404
[2026-11-13T16:00:43.630Z] "GET /nothing HTTP/1.1" 404 - via_upstream - "-" 0 275 4 4 "-" "curl/8.11.1" "7cb76dab-7cfb-47ce-908a-a784d42b6142" "details:9080" "[2a01:4f8:c016:4db6::1:c60a]:9080" outbound|9080||details.default.svc.cluster.local [2a01:4f8:c016:4db6::1:c616]:41934 [fd00:10:96::2:c6c3]:9080 [2a01:4f8:c016:4db6::1:c616]:56328 - default
```

`404`, with an upstream host and `via_upstream`: the request reached the application, and the **application** said `404`. This is the first question in every investigation: did the error come from the application or from the mesh?

## When to use what

| Question | Tool |
|---|---|
| Do packets arrive at the node or the pod at all? | `tcpdump` |
| Which request, which path, which answer, how long? | access log |
| Did the application answer, or Envoy? | access log: upstream host and response flags |
| Where did one request go, across several services? | access log: the request ID |
| What does Envoy have configured? | `istioctl proxy-config` (see [Trainer demo](../traffic-management/01-trainer-demo-shifting-fault-injection-broken-rule.md)) |

## Clean up

```
kubectl delete -f telemetry-access-log.yml
```

Previous: [ControlZ](02-controlz.md)

Next: [Test a connection between two pods, and read a hidden REST call](04-test-a-connection-and-read-a-rest-call.md)
