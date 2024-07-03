project: "Switchboard Oracle Stack"
version: "0.35.2"

repositories:
  - name: intel
    url: https://intel.github.io/helm-charts/
  - name: infisical-helm-charts
    url: https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/
  - name: ingress-nginx
    url: https://kubernetes.github.io/ingress-nginx
  - name: jetstack
    url: https://charts.jetstack.io
  - name: vm
    url: https://victoriametrics.github.io/helm-charts/
  - name: switchboard-xyz
    url: switchboard-xyz.github.io/helm-charts



# General options
.options: &options
  wait: true
  wait_for_jobs: true
  force: false
  timeout: 5m
  atomic: false
  max_history: 10
  create_namespace: true


releases:
{{- with readFile "vars.yaml" | fromYaml | get "releases" }}
{{ range $v := . }}

#################################
#                               #
#      {{ $v | get "name" }}
#                               #https://charts.jetstack.io
#################################
- name: {{ $v | get "name" }}
  chart:
    name: {{ $v | get "repo" }}/{{ $v | get "name" }}
    version: {{ $v | get "version" }}
  namespace: {{ $v | get "name" }}
  tags: [{{ $v | get "name" }}]
  values:
    - values/{{ $v | get "name" }}.yml
  <<: *options

{{ end }}
{{- end }}

