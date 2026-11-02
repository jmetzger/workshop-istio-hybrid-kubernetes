# Check the link between two clusters

## Background

Two clusters form one mesh when each `istiod` can read the services and endpoints of the other cluster. For this, every cluster holds a **remote secret**: a small kubeconfig that gives its `istiod` read access to the API server of the other cluster.

If a remote secret is missing or broken, nothing fails loudly. The other cluster is simply not part of the mesh, and traffic stays local. The command that shows this is:

```
istioctl remote-clusters
```

In this exercise you read the output, break the link on purpose, see what happens, and repair it.

All commands run on your bastion host. Replace the contexts with the ones of your two clusters:

```
export CTX_A=<context of cluster A>
export CTX_B=<context of cluster B>
```

The cluster names in the outputs below (`cluster-h6`, `cluster-h6b`) are the names in our test lab. Yours may differ.

## Step 1: Prepare a test service in both clusters

`helloworld` runs in version v1 only in cluster A and in version v2 only in cluster B. Cluster A also gets a client pod (`sleep`). The sample files come from the Istio release folder (`istio-1.29.9/samples`).

```
for CTX in $CTX_A $CTX_B; do
  kubectl --context $CTX create namespace helloworld
  kubectl --context $CTX label namespace helloworld istio-injection=enabled
  kubectl --context $CTX apply -n helloworld -f samples/helloworld/helloworld.yaml -l service=helloworld
done
kubectl --context $CTX_A apply -n helloworld -f samples/helloworld/helloworld.yaml -l version=v1
kubectl --context $CTX_B apply -n helloworld -f samples/helloworld/helloworld.yaml -l version=v2
kubectl --context $CTX_A apply -n helloworld -f samples/sleep/sleep.yaml
kubectl --context $CTX_A wait -n helloworld --for=condition=Ready pod --all --timeout=180s
kubectl --context $CTX_B wait -n helloworld --for=condition=Ready pod --all --timeout=180s
```

## Step 2: Look at the link

```
istioctl --context $CTX_A remote-clusters
```

```
NAME            SECRET                                           STATUS     ISTIOD
cluster-h6                                                       synced     istiod-7b66fbd84c-g682b
cluster-h6b     istio-system/istio-remote-secret-cluster-h6b     synced     istiod-7b66fbd84c-g682b
```

Read it column by column:

| Column | Meaning |
|---|---|
| NAME | a cluster this `istiod` knows |
| SECRET | the remote secret it uses to reach that cluster. The first line is the local cluster and has no secret. |
| STATUS | `synced` means `istiod` has read the registry of that cluster |
| ISTIOD | the `istiod` pod that reports this |

Now look from cluster B:

```
istioctl --context $CTX_B remote-clusters
```

Each cluster needs a secret for the **other** one. Cluster A holds the secret for B, and cluster B holds the secret for A. Both lines must say `synced`.

## Step 3: See the effect on traffic

The client in cluster A calls `helloworld` 40 times:

```
kubectl --context $CTX_A exec -n helloworld deploy/sleep -c sleep -- sh -c 'for i in $(seq 1 40); do curl -s http://helloworld.helloworld:5000/hello; done | grep -o "version: v[12]" | sort | uniq -c'
```

```
     22 version: v1
     18 version: v2
```

Answers come from both clusters. The client sidecar knows an endpoint in each cluster:

```
istioctl --context $CTX_A proxy-config endpoints deploy/sleep.helloworld --cluster "outbound|5000||helloworld.helloworld.svc.cluster.local"
```

```
ENDPOINT                            STATUS      OUTLIER CHECK     CLUSTER
2a01:4f8:c016:17b5::1:9133:5000     HEALTHY     OK                outbound|5000||helloworld.helloworld.svc.cluster.local
2a01:4f8:c016:a758::1:a845:5000     HEALTHY     OK                outbound|5000||helloworld.helloworld.svc.cluster.local
```

Two addresses from two different networks: one pod in each cluster.

## Step 4: Break the link

Remove the secret in cluster A that gives it access to cluster B. Use the secret name from the `SECRET` column of step 2:

```
kubectl --context $CTX_A -n istio-system delete secret istio-remote-secret-cluster-h6b
```

Wait ten seconds and look again:

```
istioctl --context $CTX_A remote-clusters
```

```
NAME           SECRET     STATUS     ISTIOD
cluster-h6                synced     istiod-7b66fbd84c-g682b
```

The line for cluster B is gone. There is no error message anywhere. Repeat the calls of step 3:

```
     40 version: v1
```

All 40 answers come from v1 and the client knows only one endpoint. Cluster B is not part of the mesh any more.

**Take-away:** If traffic does not reach the other cluster and there is no error, run `istioctl remote-clusters` first. A missing line (or a status other than `synced`) shows that the link is the problem.

## Step 5: Repair the link

A remote secret for cluster B is created **in cluster B** (it needs the address and a reader account of that cluster) and applied **in cluster A**:

```
istioctl --context $CTX_B create-remote-secret --name=cluster-h6b | kubectl --context $CTX_A apply -f -
```

```
secret/istio-remote-secret-cluster-h6b created
```

The `--name` is the cluster name of B (the first column of step 2). After ten seconds:

```
istioctl --context $CTX_A remote-clusters
```

Both lines are back and say `synced`. Repeat the calls of step 3: answers from v1 and v2 again (for example 23 and 17).

## Clean up

```
kubectl --context $CTX_A delete namespace helloworld
kubectl --context $CTX_B delete namespace helloworld
```

## Summary

| Question | Command |
|---|---|
| Does this `istiod` see the other cluster? | `istioctl remote-clusters` |
| Which proxies are connected to `istiod`? | `istioctl proxy-status` |
| Which endpoints does a sidecar know? | `istioctl proxy-config endpoints <pod>` |
| How do I join a cluster? | `istioctl create-remote-secret` in the other cluster, applied here |

Keep the difference in mind: `remote-clusters` shows the link between the **control planes**, `proxy-status` shows which **proxies** are connected to each `istiod`.
