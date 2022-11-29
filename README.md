## Purpose

This plugin allows ArgoCD to manage applications defined using Helmfile

## Prerequisite

In order to test this plugin you need a Kubernetes cluster (it can even be a local k3s cluster running on a multipass VM). Also, make sure you have:
- Helm ([https://github.com/helm/helm/releases](https://github.com/helm/helm/releases))
- helm-diff plugin ([https://github.com/databus23/helm-diff](https://github.com/databus23/helm-diff))
- Helmfile ([https://github.com/helmfile/helmfile#installation](https://github.com/helmfile/helmfile#installation))

Ex: installation on Linux / amd64
```
OS=linux     # change to match your current os (linux / darwin)
ARCH=amd64   # change to match your current architecture (amd64 / arm64)

# Helm
curl -sSLO https://get.helm.sh/helm-v3.10.2-$OS-$ARCH.tar.gz
tar zxvf helm-v3.10.2-$OS-$ARCH.tar.gz
sudo mv ./$OS-$ARCH/helm /usr/local/bin

# Helm-diff
helm plugin install https://github.com/databus23/helm-diff

# Helmfile
curl -sSLO https://github.com/helmfile/helmfile/releases/download/v0.148.1/helmfile_0.148.1_$OS_$ARCH.tar.gz
tar zxvf helmfile_0.148.1_$OS_$ARCH.tar.gz
sudo mv ./helmfile /usr/local/bin/
```

## Installation of ArgoCD + the helmfile plugin

There are currently 2 installation options in this repo:
- a quick path to install ArgoCD and its Helmfile plugin in 2 commands
- a detailed path to understand the installation steps

### Quick path

Use the following command (make sure you have the prerequisites first) which creates a Helmfile defining ArgoCD + the helmfile plugin:

```
cat <<EOF > helmfile.yaml
repositories:
  - name: argo
    url: https://argoproj.github.io/argo-helm

releases:
  - name: argo
    namespace: argo
    labels:
      app: argo
    chart: argo/argo-cd
    version: ~5.14.1
    values:
    - repoServer:
        extraContainers:
        - name: plugin
          image: lucj/argocd-plugin-helmfile:v0.0.10
          command: ["/var/run/argocd/argocd-cmp-server"]
          securityContext:
            runAsNonRoot: true
            runAsUser: 999
          volumeMounts:
          - mountPath: /var/run/argocd
            name: var-files
          - mountPath: /home/argocd/cmp-server/plugins
            name: plugins
EOF
```

and deploy it into the cluster:

```
helmfile apply
```

Note: this quick path does not take into account the usage of a private key to encrypt sensitive properties in the values files. If you want to use such an encryption key please read the detailed path below.

That's it, you can now go directly into the *Usage* step.

### Detailed path

If you want to understand a little bit more what is happening under the hood, you can follow the following instructions to install and configure ArgoCD + the Helmfile plugin.

The following installs ArgoCD using the helm chart available on [https://artifacthub.io/packages/helm/argo/argo-cd](https://artifacthub.io/packages/helm/argo/argo-cd)

- First option:

Using the following helm commands:

```
helm repo add argo https://argoproj.github.io/argo-helm

helm upgrade --install --create-namespace -n argo argo-cd argo/argo-cd --version 5.14.1
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
    version: ~5.14.1
```

then run the following command:

```
helmfile apply
```

Once ArgoCD is installed, we need to enable the Helmfile plugin. The binaries needed for the plugin are currently packaged into the following image in the DockerHub: [https://hub.docker.com/r/lucj/argocd-plugin-helmfile/tags](https://hub.docker.com/r/lucj/argocd-plugin-helmfile/tags)

Follow the steps below to make sure ArgoCD can use this plugin:

- creation of a age.key

This steps allows an admin to encrypt yaml files containing sensitive values and commit them into git. ArgoCD will use this key to decrypt the secrets before it can install/update an application.

First make sure you have age installed ([https://github.com/FiloSottile/age](https://github.com/FiloSottile/age)), then create a key:  

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

Create the following ArgoCD Application resource which defines the VotingApp, a sample microservice application. ArgoCD will automatically deploy this application using the helmfile plugin.

```
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: votingapp
  namespace: argo
  finalizers:
    - resources-finalizer.argocd.argoproj.io
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

ArgoCD web interface show the app deployed and in sync

![ArgoCD](./images/argocd-votingapp1.png)

![ArgoCD](./images/argocd-votingapp2.png)

You will then be able to vote for your favorite pet and see the result:
- the vote UI is exposed as a NodePort service (available on port 31000)
- the result UI is exposed as a NodePort service (available on port 31001)

![Vote UI](./images/vote.png)

![Result UI](./images/result.png)

## About secret encryption

If you installed ArgoCD and its helmfile plugin using the detailed path above you also created a *key.txt* age key. [age](https://github.com/FiloSottile/age) is one the encryption methods that can be used by [SOPS](https://github.com/mozilla/sops) to encrypt/decrypt environment values. As Helmfile knows how to use SOPS we can provide the age key to the ArgoCD helmfile plugin. Doing so we can reference encrypted values in the Helmfile definition of an application and let the plugin decrypt data when it needs to do so.

Let's consider a simple example: we have an application which needs to be provided the password to connect to a Postgres database. As we do not want this password to be in plain tewt in the values file, we will encrypt it first and then use the encrypted version in the Helmfile definition of the application. Let's detail those 2 steps:

Note: for this example, we use a dummy age key with the following content:
```
# created: 2022-11-01T10:06:45+01:00
# public key: age1px36dnru88xffdnejh2ps0grsz9cygx05f8wa8ly47duxm7lyq4ql3rxcm
AGE-SECRET-KEY-1U3TRUW0NMRKH348F2870AYRYTDZZ4VD759GCXKC3MCWJRCG0N7JQXZ0L8F
```

- data encryption

First we need to install SOPS binary on our local machine. It can be downloaded from [https://github.com/mozilla/sops/releases](https://github.com/mozilla/sops/releases).

Next let's consider the following *secrets.yaml* containing the password needed by the application:

```
# secrets.yaml
postgres:
  password: my_password
```

In order to store this file in a more secure way we can encrypt it with SOPS using the age key created above:

```
# Provide SOPS the path towards the age key
export SOPS_AGE_KEY_FILE=$PWD/key.txt

# Provide SOPS a list of public keys which will be able to decrypt the data (only the current key here but additional ones could be added)
SOPS_AGE_RECIPIENTS=age1px36dnru88xffdnejh2ps0grsz9cygx05f8wa8ly47duxm7lyq4ql3rxcm

# Encrypt the secrets.yaml file
sops encrypt secrets.yaml
```

Once encrypted the content of the *secrets.yaml* file is modified as follows:

```
$ cat secrets.yaml
postgres:
    password: ENC[AES256_GCM,data:VsgiSvbMxg6fVj0=,iv:6Umsg2X5bRL8NE6npmqiSKPOht9Lp4JzBxbBGRVYLRA=,tag:KCzMX3eeQcSwOSC9k7umxQ==,type:str]
sops:
    kms: []
    gcp_kms: []
    azure_kv: []
    hc_vault: []
    age:
        - recipient: age1px36dnru88xffdnejh2ps0grsz9cygx05f8wa8ly47duxm7lyq4ql3rxcm
          enc: |
            -----BEGIN AGE ENCRYPTED FILE-----
            YWdlLWVuY3J5cHRpb24ub3JnL3YxCi0+IFgyNTUxOSBlSVdhSE9VWEM2QVZsVndt
            YlFmMTRqRVlpcVYrVStnb0tUVGZWdDFCRHpVCm9oWW02TDk1ZktMUXB5T1I3aGtJ
            aURDMldGUGtkeGRSbVF6MzRQWHV2UjQKLS0tIFpBdllOTWk2K0U1UnF1bmExTkt3
            WHdUWGs2dnZwdGZhQmw0aXlBUkNOQUkKz2qlK3EgIZ6CyJNoJEVutSsDIsTFPpgi
            Rs0gKpCFW39EzIXHPov6GsnztiNmYv9lVUlbDHGumsA5Ezr0axv0aw==
            -----END AGE ENCRYPTED FILE-----
    lastmodified: "2022-11-27T14:25:50Z"
    mac: ENC[AES256_GCM,data:TbNaZ8g7yxjXzMcnYbPKpK1ukg8wDXBk6AhxqFWqJkemwPAjuUxKyQoUO08xQ4wvZyQuPWDYOehHW18usuL3LGJt0yhJOnyKdZY8o0kU0AniYp+KfrhAlwuZ5vfWTbBLbrC7P2+1u/2L/clSH1I8J8zk9hVXMAnlt/QYi0HGr48=,iv:JSW1MO5kWC4N+Snc/+q7cnM04PCAl6bwV7hgETyslgs=,tag:tidkPm6eZoKYP98wYNrmFQ==,type:str]
    pgp: []
    unencrypted_suffix: _unencrypted
    version: 3.7.3
```

The *postgres.password* value is now encrypted and can only be decrypted using the public key provided in the *SOPS_AGE_RECIPIENTS* environment variable.

- helmfile

We can now reference the *secrets.yaml* file in the Helmfile definition of an application as follows:

Note: Helmfile tries to decrypt the content of properties in files defined under the *secrets* property of a release

```
releases:
  - name: myapp
    namespace: myapp
    chart: .
    version: ~0.0.1
    values:
      - values.yaml  <- Helmfile considers plain text valued are provided
    secrets:
      - secrets.yaml <- Helmfile considers encrypted values are provided
```

As the age key is given to the ArgoCD's helmfile plugin, each time the above application needs to be deployed / updated the plugin will be able to use this key to decrypt the properties first.

Note: *age* is one of the encryption method that is supported by SOPS (and thus by Helmfile). Other encryption methods exist but they are not taken into account in this plugin.

## Status

This is currently a work in progress. Feel free to give it a try and provide feedback :)

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

