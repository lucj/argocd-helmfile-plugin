--- WIP: this has not been tested yet ---

## Purpose

ArgoCD plugin allowing to handle applications defined with Helmfile

## Installation instruction

Note: the following assumes argoCD has been installed using the helm chart available on [https://artifacthub.io/packages/helm/argo/argo-cd](https://artifacthub.io/packages/helm/argo/argo-cd)

The binary needed for the plugin are currently packaged into a temporary image on the DockerHub: [https://hub.docker.com/r/lucj/argocd-plugin-helmfile/tags](https://hub.docker.com/r/lucj/argocd-plugin-helmfile/tags)

Follow the steps below to make sure argoCD can use this plugin:

- creation of a age.key to be used by sops so argoCD can decrypt secret

```
age-keygen > key.txt
```

- create a secret from this key

```
kubectl -n argo create secret generic age --from-file=./key.txt
```

- in the argoCD values.yaml, define an additional volume (containing this new secret) in the repo-server pod

```
repoServer:
  volumes:
    - name: age
      secret:
        secretName: age
```

- still in the argoCD values.yaml, define an extraContainer (sidecar container containing the plugin) and give it access to the age key

```
repoServer:
  volumes:
    - name: age
      secret:
        secretName: age

  extraContainers:
  - name: plugin
    image: lucj/argocd-plugin-helmfile:v0.0.1
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

- update argoCD using the updated values.yaml

## Usage

Definition of an application that should be managed via this plugin

```
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: votingapp
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://gitlab.com/voting-application/config.git
    targetRevision: master
    path: helm
    plugin: {}
```

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

