# Expose Bookinfo through the ingress gateway over IPv6

## Background

Your lab has an Istio ingress gateway in the namespace `istio-ingress`. It is a normal Kubernetes Service of type `LoadBalancer`, IPv6 single stack. Two things make it reachable from other clusters and from outside the lab:

| Part | What it does |
|---|---|
| Fixed address | Every lab server owns a whole `/64` network, routed to it by the provider. MetalLB hands out one fixed address from that `/64` to the gateway (`...::2:1`). No floating IP and no cloud load balancer is needed. |
| Cloud firewall | Allows TCP 80 and 443 from the internet. Everything else (SSH, API server, kubelet) stays closed. |

In this exercise you publish the demo application Bookinfo through this gateway and call it from different places.

All commands run on your bastion host, in cluster A. The sample files come from the Istio release folder (`istio-1.29.9/samples`).

## Step 1: Look at the gateway Service

```
kubectl get svc istio-ingressgateway -n istio-ingress
```

Expected output (addresses differ in your lab):

```
NAME                   TYPE           CLUSTER-IP          EXTERNAL-IP               PORT(S)
istio-ingressgateway   LoadBalancer   fd00:10:96::c:15b   2a01:4f8:c016:dab1::2:1   15021:31361/TCP,80:32665/TCP,443:31613/TCP
```

The EXTERNAL-IP is an IPv6 address. Check the address family and the target ports:

```
kubectl get svc istio-ingressgateway -n istio-ingress -o jsonpath='{.spec.ipFamilyPolicy} {.spec.ipFamilies}{"\n"}'
kubectl get svc istio-ingressgateway -n istio-ingress -o jsonpath='{.spec.ports[*].targetPort}{"\n"}'
```

```
SingleStack ["IPv6"]
15021 8080 8443
```

Port 80 of the Service leads to port **8080** of the gateway pod. The gateway pod does not run as root, so Envoy cannot listen on port 80 inside the pod. Keep this in mind, it matters in step 6.

## Step 2: Deploy Bookinfo

```
kubectl label namespace default istio-injection=enabled --overwrite
kubectl apply -f samples/bookinfo/platform/kube/bookinfo.yaml
kubectl wait --for=condition=Ready pod --all -n default --timeout=300s
```

Every pod shows `2/2` (application and sidecar):

```
kubectl get pods -n default
```

## Step 3: Publish it with a Gateway and a VirtualService

```
kubectl apply -f samples/bookinfo/networking/bookinfo-gateway.yaml
kubectl get gateway,virtualservice -n default
```

```
NAME                                           AGE
gateway.networking.istio.io/bookinfo-gateway   5s

NAME                                          GATEWAYS               HOSTS   AGE
virtualservice.networking.istio.io/bookinfo   ["bookinfo-gateway"]   ["*"]   5s
```

## Step 4: Call Bookinfo

```
export GATEWAY=$(kubectl get svc istio-ingressgateway -n istio-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo $GATEWAY
curl -6 -s -o /dev/null -w "HTTP %{http_code}\n" "http://[$GATEWAY]/productpage"
```

```
HTTP 200
```

An IPv6 address in a URL needs square brackets. Without them `curl` reads the colons as a port.

Look at the content, the page shows the reviews and ratings that come from other pods:

```
curl -6 -s "http://[$GATEWAY]/productpage" | grep -E "<title>|Book Reviews|Reviewer"
```

## Step 5: See what the gateway listens on

```
export GWPOD=$(kubectl get pod -n istio-ingress -l istio=ingressgateway -o jsonpath='{.items[0].metadata.name}')
istioctl proxy-config listener $GWPOD.istio-ingress
```

```
ADDRESSES PORT  MATCH DESTINATION
::        8080  ALL   Route: http.8080
::        15021 ALL   Inline Route: /healthz/ready*
::        15090 ALL   Inline Route: /stats/prometheus*
```

The addresses are `::`, not `0.0.0.0`. Envoy in an IPv6 single stack cluster listens on IPv6 only. The listener for your Gateway resource (port 80) is on 8080, as seen in step 1.

## Step 6: Call it from other places

The gateway address is reachable from everywhere that has IPv6 connectivity to your lab:

| Caller | Command | Expected |
|---|---|---|
| A node of the other cluster (cluster B) | `curl -6 -s -o /dev/null -w "HTTP %{http_code}\n" "http://[$GATEWAY]/productpage"` | HTTP 200 |
| A host outside the lab with IPv6 (for example the trainer's machine) | the same command | HTTP 200 |
| A host with IPv4 only | cannot work, there is no IPv4 address anywhere in the lab | no connection |

If the call ends immediately with `Connection refused` although the Service has an endpoint, check the `targetPort` of the Service (step 1). With `targetPort` 80 the traffic arrives at a port where nothing listens. A quick test:

```
kubectl get endpointslice -n istio-ingress
```

The endpoint list is fine in that case, only the port is wrong. That is why this problem is easy to overlook.

## Limits to know

* The fixed address belongs to the `/64` of **one** node. If this node is down, the address is gone, even if the gateway pod runs on another node.
* `externalTrafficPolicy: Cluster` (the default) hides the real client address from the gateway (source NAT).

## Clean up

Keep Bookinfo, the next exercises use it. If you want to remove it:

```
kubectl delete -f samples/bookinfo/networking/bookinfo-gateway.yaml
kubectl delete -f samples/bookinfo/platform/kube/bookinfo.yaml
```
