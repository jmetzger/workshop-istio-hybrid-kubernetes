# Health check: is the application on the VM alive?

## What we do

A pod has readiness probes: the kubelet asks the application, and Kubernetes knows whether it is alive. A VM has no kubelet. Without a health check the mesh only knows that the sidecar of the VM is connected, not whether the application behind it answers. You see this, then you add a `probe` to the `WorkloadGroup` and see the difference.

Prerequisite: the VM is in the mesh ([Add a virtual machine to the mesh](01-add-a-vm-to-the-mesh.md)) and the test pod `client` runs in cluster a. Measured in our lab: Istio 1.29.9, VM with IPv6 only.

All commands run on your bastion host as your lab user.

```
export CTX_A=cluster-a
export VM=a-vm1
cd ~/vm-in-the-mesh
```

## Step 1: Without a probe the mesh knows nothing

The `WorkloadEntry` of the VM has no health status:

```
kubectl --context $CTX_A get workloadentry -n vm -o jsonpath='{range .items[*]}{.metadata.name}{" "}{range .status.conditions[*]}{.type}={.status} ({.message}) {end}{"\n"}{end}'
```

```
diameter-adapter-2a01-4f8-c014-77c2--1-net1 
```

Stop the application on the VM. The sidecar keeps running:

```
ssh $VM "systemctl stop vm-echo"
```

Nothing changes in the mesh. The `WorkloadEntry` looks the same, and the Envoy of the caller still has the VM as a healthy endpoint:

```
istioctl --context $CTX_A proxy-config endpoints deploy/client --cluster "outbound|8000||diameter-adapter.vm.svc.cluster.local"
```

```
ENDPOINT                       STATUS      OUTLIER CHECK     CLUSTER
2a01:4f8:c014:77c2::1:8000     HEALTHY     OK                outbound|8000||diameter-adapter.vm.svc.cluster.local
```

Only the call itself tells the truth:

```
kubectl --context $CTX_A exec deploy/client -c curl -- curl -s -m 5 -o /dev/null -w "HTTP %{http_code}\n" http://diameter-adapter.vm.svc.cluster.local:8000/
```

```
HTTP 503
```

Start the application again:

```
ssh $VM "systemd-run --unit vm-echo python3 /root/vm-echo-server.py"
```

## Step 2: Add a probe

The probe belongs to the `WorkloadGroup`. `04-workloadgroup-probe.yml` is the file `02-workloadgroup.yml` with a `probe` at the end:

```
apiVersion: networking.istio.io/v1
kind: WorkloadGroup
metadata:
  name: diameter-adapter
  namespace: vm
spec:
  metadata:
    labels:
      app: diameter-adapter
  template:
    serviceAccount: diameter-adapter
    network: net1
    ports:
      http: 8000
  probe:
    periodSeconds: 3
    failureThreshold: 2
    httpGet:
      port: 8000
      path: /
```

```
kubectl --context $CTX_A apply -f 04-workloadgroup-probe.yml
```

That alone changes nothing on the VM. It is the **agent on the VM** that runs the probe, and it reads the probe from its own configuration file. Create the files again and compare:

```
export ISTIOD_ADDR=$(kubectl --context $CTX_A -n istio-system get svc istiod-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
istioctl --context $CTX_A x workload entry configure -f 04-workloadgroup-probe.yml -o vmfiles-probe --clusterID cluster-a --ingressIP $ISTIOD_ADDR --autoregister
diff <(ssh $VM cat /etc/istio/config/mesh) vmfiles-probe/mesh.yaml
```

```
18a19,24
>   readinessProbe:
>     failureThreshold: 2
>     httpGet:
>       path: /
>       port: 8000
>     periodSeconds: 3
```

Copy the new `mesh.yaml` (and the fresh token) to the VM and restart the sidecar:

```
scp -q vmfiles-probe/mesh.yaml $VM:/etc/istio/config/mesh
scp -q vmfiles-probe/istio-token $VM:/var/run/secrets/tokens/istio-token
ssh $VM "chown istio-proxy: /etc/istio/config/mesh /var/run/secrets/tokens/istio-token; systemctl restart istio"
```

After half a minute the `WorkloadEntry` has a status:

```
diameter-adapter-2a01-4f8-c014-77c2--1-net1 Healthy=True () 
```

The log of the agent on the VM (`/var/log/istio/istio.log`):

```
info	healthcheck	starting health check for health.AggregateProber in 0s
info	healthcheck	success threshold hit, marking as healthy
```

## Step 3: Stop the application again

```
ssh $VM "systemctl stop vm-echo"
```

Six seconds later (two failed probes, three seconds apart) the agent reports it, and the `WorkloadEntry` says why:

```
diameter-adapter-2a01-4f8-c014-77c2--1-net1 Healthy=False (Get "http://[2a01:4f8:c014:77c2::1]:8000/": dial tcp [::6]:0->[2a01:4f8:c014:77c2::1]:8000: connect: connection refused) 
```

Now you can see from the cluster, with `kubectl`, that the application on the VM is down, and why. The call still answers `HTTP 503`: there is only this one VM behind the service. In our measurement, ten seconds after the stop, the Envoy of the caller still listed the endpoint.

Start the application:

```
ssh $VM "systemd-run --unit vm-echo python3 /root/vm-echo-server.py"
```

A few seconds later the status is `Healthy=True` again and the call answers `HTTP 200`.

## What to take away

* `proxy-status` says that the **sidecar** of the VM is connected. Only a `probe` says whether the **application** answers.
* The probe runs on the VM. After a change of the `WorkloadGroup` the VM needs the new `mesh.yaml`.
* The reason for an unhealthy VM is in the status of the `WorkloadEntry` and in `/var/log/istio/istio.log` on the VM.
* IPv6 only: the probe works without any extra setting. On a VM with IPv4 **and** IPv6 it needs workarounds, see [Dual stack on the VM: what to set](00-dual-stack-switches.md).
