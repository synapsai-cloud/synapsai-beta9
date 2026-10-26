{{- define "beta9.init" -}}
  {{/* Hack to disable main controller */}}
  {{- $_ := include "beta9.disable-main-controller" . | fromYaml | merge .Values -}}

  {{/* Make sure all variables are set properly */}}
  {{- include "bjw-s.common.loader.init" . }}

  {{/* Enforce default values */}}
  {{- $_ := include "beta9" . | fromYaml | merge .Values -}}
{{- end -}}

{{/* The stamped config and pod checksum must describe the same release. */}}
{{- define "beta9.config" -}}
{{- $config := deepCopy (default dict .Values.config) -}}
{{- $gateway := get $config "gatewayService" | default dict -}}
{{- $_ := set $gateway "deploymentRevision" .Release.Revision -}}
{{- $_ := set $config "gatewayService" $gateway -}}
{{- toYaml $config -}}
{{- end -}}


{{/* Disable main controller */}}
{{- define "beta9.disable-main-controller" -}}
controllers:
  main:
    enabled: false
service:
  main:
    enabled: false
ingress:
  main:
    enabled: false
route:
  main:
    enabled: false
serviceMonitor:
  main:
    enabled: false
networkpolicies:
  main:
    enabled: false
{{- end -}}


{{/* Define hard coded defaults */}}
{{- define "beta9" -}}
controllers:
  gateway:
    type: deployment
    pod:
      annotations:
        secret-hash: {{ include "sha256sum" (include "beta9.config" .) }}
    containers:
      main:
        # The published config file has no passwords. This writes /etc/beta9.d/credentials.yaml
        # from the beta9-credentials secret, then starts the gateway.
        command:
        - /bin/sh
        - -c
        - |
          set -eu
          test -n "$POSTGRES_PASSWORD"
          test -n "$REDIS_PASSWORD"
          test -n "$STORAGE_ACCESS_KEY"
          test -n "$STORAGE_SECRET_KEY"
          test -n "$ENCRYPTION_KEY"
          mkdir -p /etc/beta9.d
          cp /etc/beta9-config/config.yaml /etc/beta9.d/config.yaml
          {
            printf '%s\n' 'database:'
            printf '%s\n' '  postgres:'
            printf '%s\n' '    username: beta9'
            printf '%s\n' "    password: \"${POSTGRES_PASSWORD}\""
            printf '%s\n' "    encryptionKey: \"${ENCRYPTION_KEY}\""
            printf '%s\n' '  redis:'
            printf '%s\n' "    password: \"${REDIS_PASSWORD}\""
            printf '%s\n' 'storage:'
            printf '%s\n' '  workspaceStorage:'
            printf '%s\n' '    defaultEndpointUrl: http://beta9-minio:9000'
            printf '%s\n' '    defaultPresignedEndpointUrl: http://beta9-minio:9000'
            printf '%s\n' "    defaultAccessKey: \"${STORAGE_ACCESS_KEY}\""
            printf '%s\n' "    defaultSecretKey: \"${STORAGE_SECRET_KEY}\""
            printf '%s\n' '    defaultRegion: us-east-1'
          } > /etc/beta9.d/credentials.yaml
          exec /usr/local/bin/gateway
        env:
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: beta9-credentials
              key: postgres-password
        - name: REDIS_PASSWORD
          valueFrom:
            secretKeyRef:
              name: beta9-credentials
              key: redis-password
        - name: STORAGE_ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: beta9-credentials
              key: storage-access-key
        - name: STORAGE_SECRET_KEY
          valueFrom:
            secretKeyRef:
              name: beta9-credentials
              key: storage-secret-key
        - name: ENCRYPTION_KEY
          valueFrom:
            secretKeyRef:
              name: beta9-credentials
              key: encryption-key
        image:
          repository: {{ .Values.images.gateway.repository }}
          tag: "{{ .Values.images.gateway.tag | default .Chart.AppVersion }}"
          pullPolicy: {{ .Values.images.gateway.pullPolicy | default "IfNotPresent" }}
        probes:
          readiness:
            enabled: true
            custom: true
            spec:
              initialDelaySeconds: 5
              successThreshold: 2
              failureThreshold: 2
              periodSeconds: 3
              timeoutSeconds: 1
              grpc:
                port: 1993
                service: readiness
          liveness:
            enabled: true
            custom: true
            spec:
              initialDelaySeconds: 10
              successThreshold: 1
              failureThreshold: 10
              periodSeconds: 3
              timeoutSeconds: 1
              grpc:
                port: 1993
                service: liveness
          startup:
            enabled: true
            custom: true
            spec:
              periodSeconds: 3
              timeoutSeconds: 1
              failureThreshold: 100
              grpc:
                port: 1993
                service: liveness
        securityContext:
          privileged: true
    # Host networking would publish 1993 and 1994 on the node, past the ingress.
    hostNetwork: false
service:
  gateway:
    controller: gateway
ingress:
  gateway:
    controller: gateway
serviceAccount:
  create: true
persistence:
  config-helm:
    enabled: {{ if .Values.config }}true{{ else }}false{{ end }}
    type: secret
    name: beta9-config-helm
    globalMounts:
    - path: /etc/beta9-config/config.yaml
      subPath: config.yaml
      readOnly: true
{{- end -}}

{{/* htpasswd SHA1 ({SHA}base64), which nginx and Traefik basic auth both accept. */}}
{{- define "beta9.htpasswdSHA" -}}
{{- $hex := sha1sum . -}}
{{- $digits := dict "0" 0 "1" 1 "2" 2 "3" 3 "4" 4 "5" 5 "6" 6 "7" 7 "8" 8 "9" 9 "a" 10 "b" 11 "c" 12 "d" 13 "e" 14 "f" 15 -}}
{{- $raw := "" -}}
{{- range $i := until 20 -}}
{{- $offset := mul $i 2 -}}
{{- $hi := index $digits (substr $offset (add $offset 1) $hex) -}}
{{- $lo := index $digits (substr (add $offset 1) (add $offset 2) $hex) -}}
{{- $raw = printf "%s%c" $raw (int (add (mul $hi 16) $lo)) -}}
{{- end -}}
{{- printf "{SHA}%s" ($raw | b64enc) -}}
{{- end -}}


{{/*Adds labels to custom manifests.*/}}
{{- define "manifests.metadata" -}}
metadata:
  labels:
    {{ include "bjw-s.common.lib.metadata.allLabels" . | nindent 4 }}
{{- end -}}


{{- define "sha256sum" -}}
{{- printf "%s" (. | sha256sum) | quote -}}
{{- end -}}
