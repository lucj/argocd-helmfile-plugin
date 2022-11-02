--- This is a work in progress ---

## Purpose

ArgoCD plugin allowing to handle applications defined with Helmfile

## Installation instruction

### Prerequisite

In order to test this plugin, you only need a Kubernetes cluster. It can even be a local k3s cluster running on a multipass VM.

### ArgoCD installation

The following installs ArgoCD using the helm chart available on [https://artifacthub.io/packages/helm/argo/argo-cd](https://artifacthub.io/packages/helm/argo/argo-cd)

- First option:

Using the following helm commands:

```
helm repo add argo https://argoproj.github.io/argo-helm

helm upgrade --install --create-namespace -n argo argo-cd argo/argo-cd --version 5.12.3
```

- Second option:

Create the following helmfile.yaml:

```
repositories:
  - name: argo
    url: https://argoproj.github.io/argo-helm

releases:
  - name: argo
    namespace: argo
    labels:
      app: argo
    chart: argo/argo-cd
    version: ~5.12.3
```

then run the following command:

```
helmfile apply
```

### Helmfile plugin

The binary needed for the plugin are currently packaged into a temporary image on the DockerHub: [https://hub.docker.com/r/lucj/argocd-plugin-helmfile/tags](https://hub.docker.com/r/lucj/argocd-plugin-helmfile/tags)

Follow the steps below to make sure ArgoCD can use this plugin:

- creation of a age.key

We can use this one to encrypt secrets values that argo-cd will be able to decrypt.

```
age-keygen > key.txt
```

- create a secret from this key

```
kubectl -n argo create secret generic age --from-file=./key.txt
```

- in the values.yaml file of ArgoCD helm chart, define an additional volume (containing this new secret) in the repo-server pod

```
repoServer:
  volumes:
    - name: age
      secret:
        secretName: age
```

- still in the values.yaml file, define an extraContainer (sidecar container containing the plugin) and give it access to the age key

```
repoServer:
  volumes:
    - name: age
      secret:
        secretName: age

  extraContainers:
  - name: plugin
    image: lucj/argocd-plugin-helmfile:v0.0.10
    command: ["/var/run/argocd/argocd-cmp-server"]
    securityContext:
      runAsNonRoot: true
      runAsUser: 999
    env:
    - name: SOPS_AGE_KEY_FILE
      value: /app/config/age/key.txt
    volumeMounts:
    - name: age
      mountPath: "/app/config/age/"
```

- also mount into this container the following volumes (plugins + var-files)

```
repoServer:
  volumes:
    - name: age
      secret:
        secretName: age

  extraContainers:
  - name: plugin
    image: lucj/argocd-plugin-helmfile:v0.0.4
    command: ["/var/run/argocd/argocd-cmp-server"]
    securityContext:
      runAsNonRoot: true
      runAsUser: 999
    env:
    - name: SOPS_AGE_KEY_FILE
      value: /app/config/age/key.txt
    volumeMounts:
    - name: age
      mountPath: "/app/config/age/"
    - mountPath: /var/run/argocd
      name: var-files
    - mountPath: /home/argocd/cmp-server/plugins
      name: plugins
```


- update ArgoCD so it takes into account the new values and then the new helmfile plugin

The update can be done using the following command (if ArgoCD was installed directly with helm):

```
helm upgrade --install --create-namespace -n argo argo-cd argo/argo-cd --version 5.12.3 -f values.yaml
```

Or with this command (if ArgoCD was installed with Helmfile):

```
helmfile apply
```

## Usage

Create the following application resource. It defines the VotingApp, a sample microservice application:

```
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: votingapp
  namespace: argo
spec:
  project: default
  source:
    repoURL: https://gitlab.com/voting-application/config.git
    targetRevision: master
    path: helm
    plugin: {}
  destination:
    server: https://kubernetes.default.svc
    namespace: vote
  syncPolicy:
    automated: {}
    syncOptions:
      - CreateNamespace=true
EOF
```

ArgoCD will automatically deploy this application using the helmfile plugin.

## License

MIT License

Copyright (c) [2022]

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

