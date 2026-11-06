# Logs and log levels

When something does not work, the logs of `istiod` and of the sidecar are the first place to look. This page shows where they are, how to raise the level for a short time and how to set it for good. Everything was measured in our lab (Istio 1.29.9).

## Where the logs are

```
kubectl -n istio-system logs deploy/istiod --tail=3
kubectl logs deploy/productpage-v1 -c istio-proxy --tail=3
```

```
2026-11-06T18:30:47.047692Z	info	delta	EDS: PUSH request for node:istio-ingressgateway-78c9c8b488-qd2rr.istio-ingress resources:20 ...
2026-11-06T17:03:11.791054Z	info	xdsproxy	connected to delta upstream XDS server: istiod.istio-system.svc:15012	id=40
```

A line is: time, **level**, **scope**, message. The scope tells you which part of the program wrote it (`delta`, `ads`, `xdsproxy`, `envoy http`). The container `istio-proxy` holds the logs of the `pilot-agent` and of Envoy together. The iptables setup of the pod is in the container `istio-init`.

Default levels in our lab: `istiod` and `pilot-agent` write `info`, Envoy writes `warning`. Debug levels write many more lines, so raise a level only where you need it and reset it afterwards.

## Raise the level for a short time

This changes the running process. There is no restart.

**`istiod`:** the levels belong to *scopes*. The format is `<scope>:<level>`, several scopes are separated by a comma. Levels: `none`, `error`, `warn`, `info`, `debug`.

```
istioctl admin log
istioctl admin log --level ads:debug
istioctl admin log --log-reset
```

The first command lists the scopes, here the first rows:

```
ACTIVE SCOPE           DESCRIPTION                                              LOG LEVEL   STACK TRACE LEVEL
ads                    ads debugging                                            info        none
adsc                   adsc debugging                                           info        none
analysis               Scope for configuration analysis runtime                 info        none
```

After the second command the row of `ads` shows `debug`, after `--log-reset` it is `info` again. `ads` is the scope for the stream with which `istiod` sends the configuration to the proxies, see [xDS in Ports of istiod and of the sidecar](../fundamentals/06-ports-of-istiod-and-the-sidecar.md). `istioctl admin log` talks to `istiod` through [ControlZ](02-controlz.md).

**The sidecar (Envoy):** the levels belong to *loggers*.

```
istioctl proxy-config log deploy/productpage-v1
istioctl proxy-config log deploy/productpage-v1 --level http:debug
istioctl proxy-config log deploy/productpage-v1 -r
```

The first command lists all loggers of Envoy, all on `warning`. The second sets one logger, `-r` resets all to the default (`warning`).

## Try it: see how `istiod` pushes a change

Raise `ads`, change a harmless Istio resource and read the log:

```
istioctl admin log --level ads:debug
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: dbg-test
  namespace: default
spec:
  host: productpage
  trafficPolicy:
    loadBalancer:
      simple: ROUND_ROBIN
EOF
kubectl -n istio-system logs deploy/istiod --since=1m | grep -E "ads|debug"
```

```
2026-11-06T18:31:05.456098Z	info	ads	Push debounce stable[20] 1 for config DestinationRule/default/dbg-test: 100.264087ms since last change, 100.264017ms since last push, full=true
2026-11-06T18:31:05.456282Z	debug	ads	InitContext 2026-11-06T18:31:05Z/13 for push took 73.74µs
2026-11-06T18:31:05.456293Z	info	ads	XDS: Pushing Services:14 ConnectedEndpoints:7 Version:2026-11-06T18:31:05Z/13
```

You see that `istiod` noticed the change of `DestinationRule/default/dbg-test` and pushed to 7 connected proxies. Clean up and reset the level:

```
kubectl delete destinationrule dbg-test -n default
istioctl admin log --log-reset
```

In our lab `istiod` pushes the configuration to the sidecars as *delta* updates (only the changes). The `info` lines of the scope `delta` show it, as in the example above.

## Try it: see the requests of a sidecar

```
istioctl proxy-config log deploy/productpage-v1 --level http:debug
kubectl run curl-test --image=curlimages/curl:8.11.1 --restart=Never -- sleep 600
kubectl wait --for=condition=Ready pod/curl-test --timeout=120s
kubectl exec curl-test -c curl-test -- curl -s -o /dev/null -w "HTTP %{http_code}\n" http://productpage:9080/productpage
kubectl logs deploy/productpage-v1 -c istio-proxy --since=1m | grep http
```

```
HTTP 200
2026-11-06T18:31:14.317186Z	debug	envoy http external/envoy/source/common/http/conn_manager_impl.cc:2019	[Tags: "ConnectionId":"1146","StreamId":"4067863431051959824"] encoding headers via codec ...
2026-11-06T18:31:14.317247Z	debug	envoy http external/envoy/source/common/http/conn_manager_impl.cc:2135	[Tags: "ConnectionId":"1146","StreamId":"4067863431051959824"] Codec completed encoding stream.
```

The lines come from the logger `http` of Envoy, with the id of the connection and of the stream. Clean up and reset:

```
istioctl proxy-config log deploy/productpage-v1 -r
kubectl delete pod curl-test
```

## Set the level for good

The values of the `istiod` Helm chart (`istiod-1.29.9`). In our lab they have the defaults:

```
helm -n istio-system get values istiod -a | grep -E "^\s+(logging:|level:|logLevel:|componentLogLevel:|logAsJson:)"
```

```
    logAsJson: false
    logging:
      level: default:info
      componentLogLevel: misc:error
      logLevel: warning
```

| Helm value | Default | What it sets |
|---|---|---|
| `global.logging.level` | `default:info` | the log level of `istiod` **and** of the `pilot-agent` in every new sidecar |
| `global.proxy.logLevel` | `warning` | the level of Envoy in new sidecars |
| `global.proxy.componentLogLevel` | `misc:error` | levels of single Envoy components in new sidecars |
| `global.logAsJson` | `false` | log lines as JSON |

We checked with `helm template`: `--set-string 'global.logging.level=default:info\,ads:debug'` gives the argument `--log_output_level=default:info,ads:debug` in the Deployment of `istiod`. The sidecar values are put in when the pod is created, so they only apply to **new** pods (see [sidecar injection](../fundamentals/07-sidecar-injection.md)).

For one pod, the injection template of our lab knows the annotations `sidecar.istio.io/logLevel`, `sidecar.istio.io/componentLogLevel` and `sidecar.istio.io/agentLogLevel`. We did not try them on a pod.

## Rules of thumb

Istio itself gives no advice on log levels (the page *Component Logging* lists the levels and how to set them). These rules are our experience:

* Keep the defaults in the Helm values, in Git.
* Raise a level only for the scope or logger you need, on the one pod or on `istiod`, and **always reset it** afterwards.
* Do not use `global.logging.level` for debugging: it also changes the `pilot-agent` of every new sidecar.
* If the logs go to a central system, think about `global.logAsJson`.

Next: [ControlZ](02-controlz.md)
