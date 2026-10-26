# Beta9 for SynapsAI

This stack started as [beam-cloud/beta9](https://github.com/beam-cloud/beta9), the open-source runtime behind [Beam](https://beam.cloud). SynapsAI keeps that runtime and runs it as the compute plane for its own inference service and for client deployments. The Helm values in `deploy/charts/beta9/values.yaml` are the profile used for that: a gateway, Postgres, Redis, a GPU worker pool, and CRIU snapshot/restore. Grafana, VictoriaMetrics, blobcache, the extra cache-server DaemonSet, and the shared image volume are left off.

SynapsAI modified this program on 2026-10-25. The changes are listed in `CHANGELOG.md`. They are licensed under the GNU Affero General Public License version 3, the same license as the upstream work, and that license covers the modified program as a whole. These changes are not proprietary. See `LICENSE`.

## What this cluster runs

- Gateway on gRPC `1993` and HTTP `1994`, as a ClusterIP service. The first authorize against an empty database creates the workspace and an admin token, so the service is not published with a LoadBalancer. External HTTP goes through the ingress, which requires basic auth.
- Postgres, Redis, and MinIO. Their passwords are generated into the `beta9-credentials` secret on first install and reused after that.
- GPU workers in the `nvidia` pool (`gVisor`, `criu.mode: nvidia`). A memory checkpoint restores on a node with the same CPU features, GPU model, and driver. GPU nodes need an NVIDIA driver at or above 570.
- Workspace buckets on the in-cluster MinIO at `http://beta9-minio:9000`. The gateway replaces the upstream LocalStack `test` / `test` credentials with the generated keys.

## Installation

Run this on a Linux Kubernetes cluster whose GPU machines are nodes in that cluster. k3s is a workable choice: one server, GPU machines joined as agents. Install the NVIDIA device plugin from `manifests/kustomize/components/nvidia-device-plugin`. Worker pods run privileged.

From this directory, with `helm` and `kubectl` aimed at the cluster:

```shell
helm dependency update deploy/charts/beta9
helm upgrade --install beta9 deploy/charts/beta9 \
  --create-namespace --namespace beta9 \
  --values deploy/charts/beta9/values.yaml
```

Pin `images.gateway.tag` and `images.worker.tag` in `deploy/charts/beta9/values.yaml` to a published release before installing. An empty tag falls through to the chart `appVersion`, which is the placeholder `0.1.0`. Images are published at `public.ecr.aws/n4e0e1y0/beta9-gateway` and `public.ecr.aws/n4e0e1y0/beta9-worker`.

The gateway Service stays a ClusterIP. In-cluster clients use its DNS name, gRPC `1993` and HTTP `1994` (`kubectl get svc -n beta9`). From outside the cluster, HTTP is the ingress host `gateway.beta9.local` (set `ingress.gateway.hosts` in the values to the name you serve). The ingress user is `beta9`. The password is in the generated secret:

```shell
kubectl get secret -n beta9 beta9-credentials -o jsonpath="{.data.ingress-password}" | base64 -d
```

```shell
curl -u beta9:<ingress-password> http://gateway.beta9.local/api/v1/health
```

Install this release in the `beta9` namespace. The Traefik middleware annotation is written for that namespace. The install identity needs permission to read Secrets, because Helm reuses `beta9-credentials` on upgrade instead of generating a second password.

`make setup` is the upstream single-machine k3d development loop. It also applies the `cluster-dev` overlay, which starts the monitoring stack this profile leaves out.

## Python SDK

The SDK in `sdk/` talks to whatever gateway its context names. Install it from this tree (Python 3.8 or newer):

```shell
cd sdk
uv sync
```

`import beam` (the package SynapsAI's orchestrator uses) switches the defaults to Beam Cloud unless the gateway is set in the environment before the import. Point it at the in-cluster Service when the orchestrator runs in the cluster, or at the ingress host when it does not. The gateway token is still required. The ingress basic-auth password is a separate gate in front of that, and only for clients that come through the ingress.

```shell
GATEWAY_HOST=<gateway-service-or-ingress-host>
GATEWAY_PORT=1993
API_HOST=<gateway-service-or-ingress-host>
API_PORT=1994
BEAM_TOKEN=<workspace-token>
```

The same values can live in `~/.beam/config.ini`, which is the file the `beam` import reads:

```ini
[default]
token = <workspace-token>
gateway_host = <gateway-host>
gateway_port = 1993
api_url = http://<gateway-host>:1994
```

The `beta9` CLI from `sdk/` reads `~/.beta9/config.ini` with those same keys. With no token and an empty database, the first authorize mints the workspace and writes the admin token into that file:

```shell
GATEWAY_HOST=<gateway-host> GATEWAY_PORT=1993 beta9
```

After that, set `BEAM_TOKEN` to the saved token so the SynapsAI orchestrator deploys pods to this gateway.
