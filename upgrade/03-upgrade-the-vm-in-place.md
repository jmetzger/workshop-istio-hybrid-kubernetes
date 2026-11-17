# Upgrade a VM in place

Theory: [How the sidecar on a VM is upgraded](00-how-the-vm-sidecar-is-upgraded.md)

## What we do

A VM is in the mesh in cluster a (exercise [Add a VM to the mesh](../virtual-machines/01-add-a-vm-to-the-mesh.md), Istio 1.29.9). You upgrade `istiod` in cluster a to 1.30.8 with Helm, and then the sidecar package on the VM. A loop in a pod calls the VM twice per second, with the time, so you see what the upgrade costs.

| Step | What |
|---|---|
| 1 | Check the versions |
| 2 | Start the loop |
| 3 | Upgrade the control plane |
| 4 | Upgrade the package on the VM |
| 5 | Count the calls |
| 6 | Look at the gap (optional) |

All commands run on your bastion host as your lab user.

```
export CTX=cluster-a
export NEW=1.30.8
export VM=a-vm1
mkdir -p ~/upgrade-vm && cd ~/upgrade-vm
helm repo add istio https://istio-release.storage.googleapis.com/charts --force-update
helm repo update
```

## Step 1: Check the versions

```
istioctl --context $CTX version
istioctl --context $CTX proxy-status | grep -E "NAME|vm"
ssh $VM "dpkg -l istio-sidecar | tail -1"
```

```
client version: 1.29.9
control plane version: 1.29.9
data plane version: 1.29.9 (11 proxies)
NAME                                                    CLUSTER       ISTIOD                     VERSION     SUBSCRIBED TYPES
v6-tln12-a-vm1.vm                                       cluster-a     istiod-bcfc6b467-2d66x     1.29.9      5 (CDS,LDS,EDS,RDS,NDS)
ii  istio-sidecar  1.29.9       amd64        Istio Sidecar
```

Save the settings of `istiod`, the upgrade runs with the same values:

```
helm --kube-context $CTX -n istio-system get values istiod -o yaml > istiod-values.yaml
```

## Step 2: Start the loop

In a **second terminal**, on the bastion host. The loop runs in the pod `client`, which calls the service of the VM:

```
kubectl --context cluster-a exec deploy/client -c curl -- sh -c 'while true; do echo "$(date +%T) $(curl -s -o /dev/null -m 4 -w "%{http_code}" http://diameter-adapter.vm.svc.cluster.local:8000/)"; sleep 0.5; done' | tee ~/upgrade-vm/calls.log
```

Leave it running until step 5.

## Step 3: Upgrade the control plane

```
helm --kube-context $CTX upgrade istio-base istio/base -n istio-system --version $NEW --wait
helm --kube-context $CTX upgrade istiod istio/istiod -n istio-system --version $NEW -f istiod-values.yaml --wait --timeout 5m
```

In our lab the two commands took 15 seconds together.

```
istioctl --context $CTX version
istioctl --context $CTX proxy-status | grep -E "NAME|vm"
```

```
client version: 1.29.9
control plane version: 1.30.8
data plane version: 1.29.9 (11 proxies)
NAME                                                    CLUSTER       ISTIOD                      VERSION     SUBSCRIBED TYPES
v6-tln12-a-vm1.vm                                       cluster-a     istiod-677cd6454b-8m4rb     1.29.9      5 (CDS,LDS,EDS,RDS,NDS)
```

The control plane is new, the VM is connected to it and still has the old sidecar. The loop shows `200`.

## Step 4: Upgrade the package on the VM

Download the new package (the file is named after the version, so you can see what is installed):

```
ssh $VM "curl -fsSL https://storage.googleapis.com/istio-release/releases/$NEW/deb/istio-sidecar.deb -o /tmp/istio-sidecar-$NEW.deb"
```

Stop the service, install the package, start the service:

```
ssh $VM "systemctl stop istio; dpkg -i /tmp/istio-sidecar-$NEW.deb; systemctl start istio; systemctl is-active istio"
```

```
Unpacking istio-sidecar (1.30.8) over (1.29.9) ...
Setting up istio-sidecar (1.30.8) ...
chown: warning: '.' should be ':': 'istio-proxy.istio-proxy'
active
```

The `chown` warning comes from the package and is harmless in our lab. The configuration and the certificates stay (`/etc/istio`, `/etc/certs`): the VM needs no new token.

```
istioctl --context $CTX proxy-status | grep -E "NAME|vm"
ssh $VM "dpkg -l istio-sidecar | tail -1"
```

```
NAME                                                    CLUSTER       ISTIOD                      VERSION     SUBSCRIBED TYPES
v6-tln12-a-vm1.vm                                       cluster-a     istiod-677cd6454b-8m4rb     1.30.8      5 (CDS,LDS,EDS,RDS,NDS)
ii  istio-sidecar  1.30.8       amd64        Istio Sidecar
```

## Step 5: Count the calls

Stop the loop in the second terminal (Ctrl+C) and count:

```
awk '{print $2}' ~/upgrade-vm/calls.log | sort | uniq -c
grep -v " 200$" ~/upgrade-vm/calls.log
```

```
    135 200
      5 503
04:49:27 503
04:49:27 503
04:49:28 503
04:49:29 503
04:49:29 503
```

In our lab: 140 calls, 5 of them `503`, all within about 3 seconds, while the sidecar on the VM went down and came back. The upgrade of `istiod` cost no call. One VM, two calls per second: this is a small test, not a proof for production load.

## Step 6: Look at the gap (optional)

Why `503`? Stop the service on the VM and look at what is left:

```
ssh $VM "systemctl stop istio; sleep 2; systemctl is-active istio; ss -ltn | grep -c :8000; ip6tables-save -t nat | grep -c 15006"
kubectl --context $CTX exec deploy/client -c curl -- curl -s -m 6 -w "\nHTTP %{http_code}\n" http://diameter-adapter.vm.svc.cluster.local:8000/
```

```
inactive
1
0
upstream connect error or disconnect/reset before headers. retried and the latest reset reason: remote connection failure, transport failure reason: TLS_error:|268435703:SSL routines:OPENSSL_internal:
HTTP 503
```

The service is `inactive`, but the application still listens on port 8000 (`1`), and there are no redirect rules to the sidecar (`0`). The sidecar in the pod speaks mTLS to that port, the application answers in plain text: `TLS_error`. Start the service again:

```
ssh $VM "systemctl start istio"
```

After about 10 seconds the call returns `HTTP 200`.

## What to take away

* **The control plane first.** A new `istiod` (1.30.8) served the VM with the old sidecar (1.29.9) without an error.
* **The gap is the restart of the sidecar on the VM.** 5 calls failed in 3 seconds, all with `503` and `TLS_error`, because the application answers while the sidecar is down.
* **A new package is not a new token.** The VM kept its configuration and its certificate, and joined again by itself.
* **The package comes from a URL, not from a repository.** Pin the version in one place.

## Clean up

This exercise leaves the lab on 1.30.8. The trainer sets the lab back (`helm rollback` of `istio-base` and `istiod`, and the VM exercise with `./vm-in-the-mesh.sh cleanup`).

With one VM there is nobody who can take the calls. What helps with two VMs: [Upgrade two VMs, one after the other](05-upgrade-two-vms-one-after-the-other.md).

Previous: [How the sidecar on a VM is upgraded](00-how-the-vm-sidecar-is-upgraded.md) | Next: [Upgrade a VM with revisions](04-upgrade-the-vm-with-revisions.md)
