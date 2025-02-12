#!/usr/bin/env bash
set -u -e

for i in \
  $(k3s \
    ctr \
    --address /run/k3s/containerd/containerd.sock \
    --namespace k8s.io i ls -q |
    awk '{print $1}'); do
  k3s ctr \
    --address /run/k3s/containerd/containerd.sock \
    --namespace k8s.io i rm $i
done
