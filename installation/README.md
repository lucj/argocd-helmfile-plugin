This folder contains an sample Helmfile which can be used to installed ArgoCD, the Helmfile plugin and create an *age* key at the same time. This gathers all the steps from the *Detailed path* in the repository's main README file. 

## Prerequisites

Make sure you have:
- Helm ([https://github.com/helm/helm/releases](https://github.com/helm/helm/releases))
- helm-diff plugin ([https://github.com/databus23/helm-diff](https://github.com/databus23/helm-diff))
- Helmfile ([https://github.com/helmfile/helmfile#installation](https://github.com/helmfile/helmfile#installation))
- age ([https://github.com/FiloSottile/age](https://github.com/FiloSottile/age))

## Installation with Helmfile

Run the following command to install ArgoCD:

```
helmfile apply
```

An age key will be automatically created in *conf/key.txt* folder unless you already have an existing key with that same name.

## Access the dashboard

- Retrieve the auto generated password:

```
kubectl -n argo get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode
```

- Port forward the frontend service:

```
kubectl -n argo port-forward service/argo-argocd-server 8080:443
```

Then open the browser on http://localhost:8080 and accept the certificate