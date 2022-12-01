To access the dashboard, first retrieve the auto generated password:

```
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode
```

Next port-forward the frontend service:

```
kubectl -n argocd port-forward service/argo-argocd-server 8080:443
```

Then open the browser on http://localhost:8080 and accept the certificate