# ControlZ: the debug page of istiod

ControlZ is the introspection interface of `istiod`: a small web interface that shows the inner state of the running program. The Istio documentation calls it "a flexible introspection framework" that "makes it easy to inspect and manipulate the internal state of an istiod instance". It listens on port `9876`.

In our lab it listens on `127.0.0.1` only, so it cannot be reached from outside the pod. You reach it with a port-forward. You already use it: `istioctl admin log` talks to `istiod` through ControlZ (the command has the flag `--ctrlz_port`, default `9876`), see [Logs and log levels](01-logs-and-log-levels.md).

## Open it

```
istioctl dashboard controlz deployment/istiod.istio-system --browser=false
```

```
http://localhost:9876
skipping opening a browser
```

The command keeps the port-forward open until you press `Ctrl-C`. With a browser on your own computer, leave out `--browser=false`. On the bastion host there is no browser: run the port-forward yourself in one terminal and use `curl` in a second terminal.

```
kubectl -n istio-system port-forward deploy/istiod 9876:9876
```

## The pages

| Page | Shows |
|---|---|
| `/scopez/` | **Logging Scopes** of `istiod`: name, description and level, the scopes that `istioctl admin log` lists |
| `/envz/` | **Environment Variables** of the process |
| `/argz/` | **Command-Line Arguments** |
| `/memz/` | **Memory Usage** |
| `/procz/` | **Process Info** |
| `/versionz/` | **Version Info** |
| `/signalz/` | **Signals** (we did not look at its content) |

`/scopez/`, `/envz/`, `/memz/` and `/procz/` also exist as JSON: `/scopej/`, `/envj/`, `/memj/` and `/procj/`.

## Try it

With the port-forward running in the other terminal:

```
curl -s localhost:9876/procj/
curl -s localhost:9876/scopej/ | head -c 250
curl -s localhost:9876/envj/ | grep -o -E '\{"name":"PILOT_ENABLE_WORKLOAD_ENTRY_AUTOREGISTRATION","value":"[^"]*"\}'
curl -s localhost:9876/memj/ | head -c 120
```

```
{"egid":1337,"euid":1337,"gid":1337,"groups":[1337],"pid":1,"ppid":0,"uid":1337,"wd":"istiod-77ddcf67cd-2djvq","hostname":"istiod-77ddcf67cd-2djvq","tempdir":"/tmp","threads":10,"goroutines":962}
[{"name":"ads","description":"ads debugging","output_level":"info","stack_trace_level":"none","log_callers":false},{"name":"adsc","description":"adsc debugging","output_level":"info","stack_trace_level":"none","log_callers":false},{"name":"analysis",
{"name":"PILOT_ENABLE_WORKLOAD_ENTRY_AUTOREGISTRATION","value":"true"}
{"Alloc":35280184,"TotalAlloc":712473592,"Sys":79653144,"Lookups":0,"Mallocs":8053762,"Frees":7810523,"HeapAlloc":352801
```

The third command answers a question that comes up often: **is a setting really switched on in `istiod`?** The variable `PILOT_ENABLE_WORKLOAD_ENTRY_AUTOREGISTRATION` is set by the VM exercise. The same works for `ISTIO_DUAL_STACK` and any other variable of `istiod`.

## What it is good for when you debug

* **Which settings does the running `istiod` really have?** `/envz/` and `/argz/` show the environment and the start arguments, not what you meant to configure.
* **Which log scopes are there, and which level do they have?** `/scopez/`, or `istioctl admin log`.
* **How much memory and how many goroutines does `istiod` use?** `/memz/` and `/procz/`, for example while you look at the resources of `istiod`.

The environment page shows **all** environment variables of `istiod`. Look at them before you share the output.

`istioctl dashboard` can open more than ControlZ (listed in our lab: `controlz`, `envoy`, `grafana`, `istiod-debug`, `jaeger`, `kiali`, `prometheus`, `proxy`, `skywalking`, `zipkin`). We only used `controlz`.

Previous: [Logs and log levels](01-logs-and-log-levels.md)
