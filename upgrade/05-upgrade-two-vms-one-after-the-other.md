# Upgrade two VMs, one after the other

Theory: [How the sidecar on a VM is upgraded](00-how-the-vm-sidecar-is-upgraded.md). This page continues [Upgrade a VM in place](03-upgrade-the-vm-in-place.md): there one VM lost 5 calls while its sidecar restarted. Here two VMs serve the same Service, and you restart them one after the other.

## What we do

Two VMs (`a-vm1` and `b-vm1`) are in the mesh and serve the Service `diameter-adapter`. You upgrade `istiod` in cluster a in place, then the sidecar package on the first VM, then on the second. A loop in a pod calls the Service five times per second. At the end you switch off the retries of the calls and restart one VM again, to see what kept the calls alive.

| Step | What |
|---|---|
| 1 | Bring the second VM into the mesh |
| 2 | Upgrade the control plane |
| 3 | Check the retries of the call |
| 4 | Start the loop |
| 5 | Upgrade the VMs one after the other |
| 6 | Count the calls |
| 7 | The same restart without retries |

All commands run on your bastion host as your lab user. The lab is at the state before the upgrade (Istio 1.29.9, one `istiod`, `a-vm1` in the mesh from the exercise [Add a VM to the mesh](../virtual-machines/01-add-a-vm-to-the-mesh.md)).

```
export CTX=cluster-a
export NEW=1.30.8
mkdir -p ~/upgrade-vm && cd ~/upgrade-vm
helm repo add istio https://istio-release.storage.googleapis.com/charts --force-update
helm repo update
helm --kube-context $CTX -n istio-system get values istiod -o yaml > istiod-values.yaml
```

## Step 1: Bring the second VM into the mesh

The script of the VM exercise takes the name of the VM. It does everything again for `b-vm1`:

```
cd ~/virtual-machines
VM=b-vm1 ./vm-in-the-mesh.sh
cd ~/upgrade-vm
```

The script ends in step 8 with `error: failed to create deployment: deployments.apps "client" already exists`, if the pod `client` from the first run is still there. The VM is in the mesh at that point (step 7). Both VMs must show up, with one `WorkloadEntry` each:

```
istioctl --context $CTX proxy-status | grep -E "NAME|vm"
kubectl --context $CTX get workloadentry -n vm
istioctl --context $CTX proxy-config endpoints deploy/client --cluster "outbound|8000||diameter-adapter.vm.svc.cluster.local"
```

```
NAME                                                    CLUSTER       ISTIOD                     VERSION     SUBSCRIBED TYPES
v6-tln12-a-vm1.vm                                       cluster-a     istiod-bcfc6b467-86h8x     1.29.9      5 (CDS,LDS,EDS,RDS,NDS)
v6-tln12-b-vm1.vm                                       cluster-a     istiod-bcfc6b467-86h8x     1.29.9      5 (CDS,LDS,EDS,RDS,NDS)
NAME                                          AGE   ADDRESS
diameter-adapter-2a01-4f8-c016-269c--1-net1   10s   2a01:4f8:c016:269c::1
diameter-adapter-2a01-4f8-c016-ec--1-net1     32s   2a01:4f8:c016:ec::1
ENDPOINT                       STATUS      OUTLIER CHECK     CLUSTER
2a01:4f8:c016:269c::1:8000     HEALTHY     OK                outbound|8000||diameter-adapter.vm.svc.cluster.local
2a01:4f8:c016:ec::1:8000       HEALTHY     OK                outbound|8000||diameter-adapter.vm.svc.cluster.local
```

The Service has no Kubernetes endpoints for the VMs (`kubectl get endpoints` shows `<none>`), the sidecar of the pod gets them from `istiod`. That is why you look at `proxy-config endpoints`.

## Step 2: Upgrade the control plane

```
helm --kube-context $CTX upgrade istio-base istio/base -n istio-system --version $NEW --wait
helm --kube-context $CTX upgrade istiod istio/istiod -n istio-system --version $NEW -f istiod-values.yaml --wait --timeout 5m
```

Download the package to both VMs now, so that the download is not part of the gap:

```
for vm in a-vm1 b-vm1; do ssh $vm "curl -fsSL https://storage.googleapis.com/istio-release/releases/$NEW/deb/istio-sidecar.deb -o /tmp/istio-sidecar-$NEW.deb"; done
```

## Step 3: Check the retries of the call

Whether a failed call is tried again is decided in the sidecar of the **calling** pod. Look at the route to the Service, from the pod `productpage-v1`:

```
istioctl --context $CTX proxy-config routes deploy/productpage-v1 --name 8000 -o json | jq -c '.[].virtualHosts[] | select(.name=="diameter-adapter.vm.svc.cluster.local:8000") | .routes[].route.retryPolicy | {retryOn, numRetries}'
```

```
{"retryOn":"connect-failure,refused-stream,unavailable,cancelled,retriable-status-codes","numRetries":2}
```

Two retries, and `retryOn` names connection failures among the reasons. Nobody set this in our lab: there is no `VirtualService` and no `DestinationRule` for `diameter-adapter`, this is the default of Istio. Without `jq` the same command without the last part prints about 70 lines. Check this in every mesh where you roll out VM upgrades: a mesh configuration or a `VirtualService` can change it.

## Step 4: Start the loop

In a **second terminal**. Five calls per second, with the time:

```
kubectl --context cluster-a exec deploy/client -c curl -- sh -c 'while true; do echo "$(date +%T) $(curl -s -o /dev/null -m 4 -w "%{http_code}" http://diameter-adapter.vm.svc.cluster.local:8000/)"; sleep 0.2; done' | tee ~/upgrade-vm/calls-two.log
```

## Step 5: Upgrade the VMs one after the other

On each VM: stop the service, install the package, start the service. Then wait until the VM is back in `proxy-status` with the new version, and only then the next VM:

```
for vm in a-vm1 b-vm1; do
  echo "### $vm"
  ssh $vm "echo stop-begin \$(date +%T); systemctl stop istio; echo stopped \$(date +%T); dpkg -i /tmp/istio-sidecar-$NEW.deb 2>&1 | grep Setting; systemctl start istio; echo started \$(date +%T)"
  until istioctl --context $CTX proxy-status | grep -q "$vm.*$NEW"; do sleep 2; done
  echo "back in proxy-status $(date +%T)"
  sleep 8
done
```

```
### a-vm1
stop-begin 05:10:02
stopped 05:10:08
Setting up istio-sidecar (1.30.8) ...
started 05:10:09
back in proxy-status 05:10:12
### b-vm1
stop-begin 05:10:21
stopped 05:10:26
Setting up istio-sidecar (1.30.8) ...
started 05:10:27
back in proxy-status 05:10:30
```

`systemctl stop istio` takes about 6 seconds: the sidecar drains before it ends. The VM is back in `proxy-status` 3 seconds after the start.

## Step 6: Count the calls

Stop the loop in the second terminal (Ctrl+C) and count:

```
awk '{print $2}' ~/upgrade-vm/calls-two.log | sort | uniq -c
grep -v " 200$" ~/upgrade-vm/calls-two.log
```

```
    189 200
```

In our lab: 189 calls over both restarts, all `200`. The same restart with one VM cost 5 calls ([Upgrade a VM in place](03-upgrade-the-vm-in-place.md)). This is a small test (one pod, five calls per second), not a proof for production load.

## Step 7: The same restart without retries

Why did no call fail? A call to the VM that goes down fails, and the sidecar of the pod tries again, now with the other VM. To see it, switch the retries off for this Service and restart `a-vm1` again (the same package, installed again):

```
cat > no-retries.yml <<'YML'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: diameter-adapter
  namespace: vm
spec:
  hosts: [diameter-adapter.vm.svc.cluster.local]
  http:
  - route:
    - destination: {host: diameter-adapter.vm.svc.cluster.local}
    retries: {attempts: 0}
YML
kubectl --context $CTX apply -f no-retries.yml
sleep 8
```

Start the loop as in step 4 (log to `calls-noretry.log`), then:

```
ssh a-vm1 "echo stop-begin \$(date +%T); systemctl stop istio; echo stopped \$(date +%T); dpkg -i /tmp/istio-sidecar-$NEW.deb 2>&1 | grep Setting; systemctl start istio; echo started \$(date +%T)"
until istioctl --context $CTX proxy-status | grep -q "a-vm1.*$NEW"; do sleep 2; done
sleep 8
```

Stop the loop and count:

```
awk '{print $2}' ~/upgrade-vm/calls-noretry.log | sort | uniq -c
grep -v " 200$" ~/upgrade-vm/calls-noretry.log
```

```
stop-begin 05:12:33
stopped 05:12:39
Setting up istio-sidecar (1.30.8) ...
started 05:12:40
     96 200
      9 503
05:12:38 503
05:12:39 503
05:12:39 503
05:12:40 503
05:12:40 503
05:12:40 503
05:12:40 503
05:12:41 503
05:12:41 503
```

Without retries 9 calls failed, from one second before `systemctl stop` returned until one second after the start. Remove the VirtualService:

```
kubectl --context $CTX delete -f no-retries.yml
```

## What to take away

* **With two VMs the restart cost no call, with one VM it cost 5.** The calls that hit the VM that goes down were tried again on the other VM.
* **The retries did it.** With `retries: attempts: 0` the same restart cost 9 calls. Do not switch the retries off for a Service that is served by VMs.
* **One VM at a time, and wait until it is back.** The loop in step 5 waits for `proxy-status` before the next VM. Two VMs down at the same time is the one-VM case again.
* **A retry repeats the call.** It is only safe for calls that may be sent twice. We did not test what a retry does to an application that must not see a call twice.
* **The VM stops answering about one second before `systemctl stop` returns.** The stop takes 6 seconds.

## What we did not test

* More than two VMs, and VMs in different networks.
* A configuration tool or a script of your own for many VMs. The loop in step 5 is the idea.
* Taking a VM out of the Service before the restart (a drain), and blue/green (a new VM joins, the old one leaves).
* `outlierDetection` in a `DestinationRule`.
* Applications that must not see a call twice.

## Clean up

This exercise leaves the lab on 1.30.8 with two VMs. The trainer sets the lab back.

Previous: [Upgrade a VM with revisions](04-upgrade-the-vm-with-revisions.md)
