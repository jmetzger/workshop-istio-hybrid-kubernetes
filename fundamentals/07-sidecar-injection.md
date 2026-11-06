# How the sidecar gets into the pod (sidecar injection)

![How the sidecar gets into the pod: kubectl apply, kube-apiserver, the injection webhook of istiod, the patch, the Pod with istio-init and istio-proxy, the kubelet](/images/sidecar-injection-flow.svg)

You do not write the sidecar into your Deployment. Istio adds it when the pod is created. This is called **injection**. It is the reason why the ports of `istiod` include `443` / `15017`: that is the door the `kube-apiserver` uses to ask `istiod` what to add to a new pod.

## The steps

1. **You create a Deployment** (`kubectl apply`) in a namespace that has the label `istio-injection=enabled`. The Deployment creates a Pod.
2. **The `kube-apiserver` receives the new Pod.** Before it stores the Pod, the admission step calls all matching *mutating webhooks*. The one from Istio is called `istio-sidecar-injector`.
3. **The webhook points to `istiod`:** the `Service` `istiod` in `istio-system`, port `443`, path `/inject`. The `Service` forwards `443` to the container port `15017` of `istiod`. The `kube-apiserver` sends the Pod and `istiod` answers.
4. **`istiod` answers with a patch.** It works out what to add from the *injection template*, which lives in the ConfigMap `istio-sidecar-injector` in `istio-system`. The `kube-apiserver` applies the patch and stores the changed Pod.
5. **The kubelet starts the Pod.** First the init container `istio-init` (it sets the iptables rules of the pod), then `istio-proxy`, then your application. When `istio-proxy` starts, its `pilot-agent` connects to `istiod` on `15012`, as described in [Ports of istiod and of the sidecar](06-ports-of-istiod-and-the-sidecar.md).

## Which pods get a sidecar

| What you do | Result | Seen in our lab |
|---|---|---|
| namespace without a label | no sidecar | pod `a`: `1/1`, no init containers |
| namespace with `istio-injection=enabled` | sidecar | pod `b`: `2/2`, init containers `istio-init` and `istio-proxy` |
| namespace with the label, but the pod has the label `sidecar.istio.io/inject=false` | no sidecar | pod `c`: no init containers |

The Istio documentation names more switches: with control plane revisions the label `istio.io/rev` is used instead of `istio-injection` (if both are set, `istio-injection` takes precedence), and `sidecar.istio.io/inject` can also be set to `"true"` on a single pod. If either label says "disabled", the pod is not injected.

**Pods that are already running are not changed.** The label is only looked at when a pod is created. In our lab pod `a` was created before the namespace got its label and stayed `1/1`. To get the sidecar into running pods, delete them: the Deployment creates new ones, and those are injected.

## What the injector adds

On a pod of our lab (Istio 1.29.9) the annotation `sidecar.istio.io/status` lists what was added:

* the init container `istio-init`
* the container `istio-proxy`. It is listed under `initContainers`, too, with `restartPolicy: Always`: a Kubernetes *native sidecar*. It starts before your application and keeps running next to it.
* volumes, among them `istio-envoy`, `istio-token`, `istiod-ca-cert` and `workload-certs` (the certificate and the token for `istiod`)

`kubectl get pod` shows `2/2` for such a pod: your application and the sidecar. The image of your application and the rest of your Deployment stay unchanged.

## The webhook in our lab

The `MutatingWebhookConfiguration` `istio-sidecar-injector` has four webhooks, one for each way to select pods (label `istio-injection`, label `istio.io/rev`, on the namespace or on the pod). All four call the same `Service`: `istiod`, port `443`, path `/inject`.

They have `failurePolicy: Fail`. That means: **if `istiod` does not answer, the `kube-apiserver` rejects the new pod.** In a labelled namespace you cannot create pods while `istiod` is down. Pods that are already running keep running.

## Look at it yourself

The commands run on your bastion host as your lab user.

```
kubectl get ns default --show-labels
kubectl get mutatingwebhookconfiguration istio-sidecar-injector -o jsonpath='{range .webhooks[*]}{.name}{" -> "}{.clientConfig.service.name}{":"}{.clientConfig.service.port}{.clientConfig.service.path}{" failurePolicy="}{.failurePolicy}{"\n"}{end}'
kubectl get pod -l app=productpage
kubectl get pod -l app=productpage -o jsonpath='{.items[0].metadata.annotations.sidecar\.istio\.io/status}'
```

### Try it: three pods, three results

```
kubectl create namespace inj-test
kubectl -n inj-test run a --image=curlimages/curl:8.11.1 --restart=Never -- sleep 3600
kubectl label namespace inj-test istio-injection=enabled
kubectl -n inj-test run b --image=curlimages/curl:8.11.1 --restart=Never -- sleep 3600
kubectl -n inj-test run c --image=curlimages/curl:8.11.1 --restart=Never --labels=sidecar.istio.io/inject=false -- sleep 3600
kubectl -n inj-test wait --for=condition=Ready pod --all --timeout=120s
kubectl -n inj-test get pod
kubectl -n inj-test get pod a b c -o custom-columns=NAME:.metadata.name,INIT:.spec.initContainers[*].name
```

```
NAME   READY   STATUS    RESTARTS   AGE
a      1/1     Running   0          6s
b      2/2     Running   0          5s
c      1/1     Running   0          5s

NAME   INIT
a      <none>
b      istio-init,istio-proxy
c      <none>
```

Pod `a` was created before the label, pod `c` has the opt-out label, only pod `b` is injected. Clean up:

```
kubectl delete namespace inj-test
```

Previous: [Ports of istiod and of the sidecar](06-ports-of-istiod-and-the-sidecar.md)
