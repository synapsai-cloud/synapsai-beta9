# Changelog

SynapsAI modified this program on 2026-10-25. The changes are licensed under the GNU Affero General Public License version 3, the same license as the upstream [beam-cloud/beta9](https://github.com/beam-cloud/beta9) work. That license covers the modified program as a whole. These changes are not proprietary.

## 2026-10-25

- Helm values in `deploy/charts/beta9/values.yaml` are the SynapsAI inference profile: a GPU pool with CRIU, idle worker capacity set to zero, and Grafana, VictoriaMetrics, blobcache, the cache-server DaemonSet, and the shared image volume left off.
- Postgres, Redis, the MinIO root credentials, the ingress basic-auth password, and the gateway encryption key are generated into the `beta9-credentials` secret. The chart no longer uses the upstream Postgres pair `root` / `password`, and Redis authentication is on.
- Workspace storage points at an in-cluster MinIO (`http://beta9-minio:9000`). The gateway overrides the upstream LocalStack endpoint and `test` / `test` keys with the generated credentials.
- The gateway Service is ClusterIP. External HTTP is an ingress with basic auth (nginx annotations and a Traefik middleware). The gateway pod does not use the host network.
