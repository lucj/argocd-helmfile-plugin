## Purpose

This plugin allows [Argo CD](https://github.com/argoproj/argo-cd) to manage applications defined with [Helmfile](https://github.com/helmfile/helmfile).

## Prerequisite

In order to test this plugin you need a Kubernetes cluster (it can even be a local k3s cluster running on a [Multipass](https://multipass.run) VM). Also, make sure you have:

- Helm ([https://github.com/helm/helm/releases](https://github.com/helm/helm/releases))
- helm-diff plugin ([https://github.com/databus23/helm-diff](https://github.com/databus23/helm-diff))
- helm-git plugin ([https://github.com/aslafy-z/helm-git](https://github.com/aslafy-z/helm-git))
- Helmfile ([https://github.com/helmfile/helmfile#installation](https://github.com/helmfile/helmfile#installation))
- age ([https://github.com/FiloSottile/age](https://github.com/FiloSottile/age))

Note: the installation of `age` is not really a requirement, but this will be useful if you need to encrypt data in values files. 

Ex: installation on Linux / amd64

```sh
OS=linux     # change to match your current os (linux / darwin)
ARCH=amd64   # change to match your current architecture (amd64 / arm64)

# Helm
HELM_VERSION=v3.17.2
curl -sSLO https://get.helm.sh/helm-${HELM_VERSION}-$OS-$ARCH.tar.gz
tar zxvf helm-${HELM_VERSION}-$OS-$ARCH.tar.gz
sudo mv ./$OS-$ARCH/helm /usr/local/bin

# Helm-diff
helm plugin install https://github.com/databus23/helm-diff

# Helmfile
HELMFILE_VERSION=0.171.0
curl -sSLO https://github.com/helmfile/helmfile/releases/download/v${HELMFILE_VERSION}/helmfile_${HELMFILE_VERSION}_${OS}_$ARCH.tar.gz
tar zxvf helmfile_${HELMFILE_VERSION}_${OS}_$ARCH.tar.gz
sudo mv ./helmfile /usr/local/bin/

# Age
AGE_VERSION=v1.2.1
curl -sSLO https://github.com/FiloSottile/age/releases/download/${AGE_VERSION}/age-${AGE_VERSION}-$OS-$ARCH.tar.gz
tar zxvf age-${AGE_VERSION}-$OS-$ARCH.tar.gz
sudo mv ./age/age /usr/local/bin/
sudo mv ./age/age-keygen /usr/local/bin/
```

## Installation of Argo CD + the Helmfile plugin

There are currently 2 installation options in this repo:
- a quick path to install Argo CD and its Helmfile plugin
- a detailed path to understand the installation steps

### Quick path

#### Without `age` key file

If you do not want to use a private key to encrypt sensitive properties in the values files you can use the following command which installs Argo CD and the Helmfile plugin using... *Helmfile*.

```bash
cat <<EOF | helmfile apply -f -
repositories:
  - name: argo
    url: https://argoproj.github.io/argo-helm

releases:
  - name: argocd
    namespace: argocd
    labels:
      app: argocd
    chart: argo/argo-cd
    version: ~7.8.23
    values:
    - repoServer:
        extraContainers:
        - name: plugin
          image: lucj/argocd-plugin-helmfile:latest
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

#### With `age` key file

If you want to use a private key to encrypt sensitive properties in the values files you can install Argo CD as follows. This will create an age key in *key.txt* of use the one already present. 

```bash
cat <<EOF | helmfile apply -f -
repositories:
  - name: argo
    url: https://argoproj.github.io/argo-helm

releases:
  - name: argocd
    namespace: argocd
    labels:
      app: argocd
    chart: argo/argo-cd
    version: ~7.8.23
    values:
      - repoServer:
          volumes:
            - name: age
              secret:
                secretName: age
          extraContainers:
          - name: plugin
            image: lucj/argocd-plugin-helmfile:latest
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
    hooks:
    - events: ["presync"]
      showlogs: true
      command: "/bin/bash"
      args:
      - "-ec"
      - |
        # Create a sops / age secret key if none already exists
        if [[ -f ./key.txt ]]; then
          echo "age key.txt file already exists"
        else
          age-keygen > ./key.txt
        fi

        # Create secret to give Argo access to the age key
        kubectl create ns argocd || true
        kubectl -n argocd create secret generic age --from-file=key.txt=./key.txt || true
    - events: ["postuninstall"]
      showlogs: true
      command: "/bin/bash"
      args:
      - "-ec"
      - |
        # Remove secret created in the presync hook
        kubectl -n argocd delete secret age
EOF
```

That's it, you can now go directly into the [*Usage*](#usage) step.

### Detailed path

If you want to understand what is happening under the hood, you can follow the instructions below to install and configure Argo CD and the Helmfile plugin manually.

The following installs Argo CD using the helm chart available on [https://artifacthub.io/packages/helm/argo/argo-cd](https://artifacthub.io/packages/helm/argo/argo-cd)

- First option:

Using the following helm commands:

```sh
helm repo add argo https://argoproj.github.io/argo-helm

helm upgrade --install --create-namespace -n argocd argo-cd argo/argo-cd --version 7.8.23
```

- Second option:

Create the following helmfile.yaml:

```sh
repositories:
  - name: argo
    url: https://argoproj.github.io/argo-helm

releases:
  - name: argocd
    namespace: argocd
    labels:
      app: argocd
    chart: argo/argo-cd
    version: ~7.8.23
```

Then, run the following command:

```sh
helmfile apply
```

Once Argo CD is installed, we need to enable the Helmfile plugin. The binaries needed for the plugin are currently packaged into the following image in the DockerHub: [https://hub.docker.com/r/lucj/argocd-plugin-helmfile/tags](https://hub.docker.com/r/lucj/argocd-plugin-helmfile/tags)

Follow the steps below to make sure Argo CD can use this plugin:

- creating an age key

This step allows an admin to encrypt YAML files containing sensitive values and commit them into git. Argo CD will use this key to decrypt the secrets before it can install/update an application.

First make sure you have age installed ([https://github.com/FiloSottile/age](https://github.com/FiloSottile/age)), then create a key:  

```sh
age-keygen > key.txt
```

- create a secret from this key

```sh
kubectl -n argocd create secret generic age --from-file=./key.txt
```

- in the values.yaml file of Argo CD helm chart, define an additional volume (containing this new secret) in the repo-server pod

```yaml
repoServer:
  volumes:
    - name: age
      secret:
        secretName: age
```

- still in the values.yaml file, define an extraContainer (sidecar container containing the plugin) and give it access to the age key

```yaml
repoServer:
  volumes:
    - name: age
      secret:
        secretName: age

  extraContainers:
  - name: plugin
    image: lucj/argocd-plugin-helmfile:latest
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

```yaml
repoServer:
  volumes:
    - name: age
      secret:
        secretName: age

  extraContainers:
  - name: plugin
    image: lucj/argocd-plugin-helmfile:latest
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

- if an environment needs to be passed to `Helmfile`
```yaml
repoServer:
  extraContainers:
    - name: plugin
      env:
        - name: ENV_NAME
          value: '{{metadata.labels.ENV_NAME}}' # or whatever env name as needed
```

- update Argo CD, so it takes into account the new values

The update can be done using the following command (if Argo CD was installed directly with helm):

```bash
helm upgrade --install --create-namespace -n argocd argo-cd argo/argo-cd --version 7.8.23 -f values.yaml
```

Or with this command (if Argo CD was installed with Helmfile):

```bash
helmfile apply
```

## Usage

Create the following Argo CD Application resource which defines the VotingApp, a sample microservice application. Argo CD will automatically deploy this application using the *helmfile.yaml* file located in the specified (demo) repository.

```bash
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: votingapp
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://gitlab.com/lucj/luc.run.git
    targetRevision: main
    path: misc/helmfiles/votingapp
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

Argo CD web interface show the app deployed and in sync

![Argo CD](./images/argocd-1.png)

![Argo CD](./images/argocd-2.png)

You are now be able to vote for your favorite pet and see the results.

Note: in this example the subdomains *vote.votingapp.cc* and *result.votingapp.cc* are mapped to the IP address of the Ingress Controller installed in a demo cluster.

![Vote UI](./images/vote.png)

![Result UI](./images/result.png)

## About secret encryption

If you installed Argo CD and its Helmfile plugin using the detailed path above, you created a *key.txt* age key. [age](https://github.com/FiloSottile/age) is an encryption method that can be used by [SOPS](https://github.com/mozilla/sops) to encrypt/decrypt environment values. As Helmfile knows how to use SOPS we can provide the age key to the Argo CD Helmfile plugin. Doing so we can reference encrypted values in the Helmfile definition of an application and let the plugin decrypt data when it needs to do so.

Let's consider a simple example. We have an application which needs to be provided the password to connect to a Postgres database. As we do not want this password to be in plain text in the values file, we first encrypt it and then use the encrypted version in the Helmfile definition of the application. Let's detail those 2 steps:

Note: for this example, we use a dummy age key with the following content.

```bash
# created: 2022-11-01T10:06:45+01:00
# public key: age1px36dnru88xffdnejh2ps0grsz9cygx05f8wa8ly47duxm7lyq4ql3rxcm
AGE-SECRET-KEY-1U3TRUW0NMRKH348F2870AYRYTDZZ4VD759GCXKC3MCWJRCG0N7JQXZ0L8F
```

- data encryption

First we need to install SOPS binary on our local machine. It can be downloaded from [https://github.com/mozilla/sops/releases](https://github.com/mozilla/sops/releases).

Next let's consider the following *secrets.yaml* containing the password needed by the application:

```yaml
# secrets.yaml
postgres:
  password: my_password
```

In order to store this file in a more secure way we can encrypt it with SOPS using the age key created above:

```bash
# Provide SOPS the path towards the age key
export SOPS_AGE_KEY_FILE=$PWD/key.txt

# Provide SOPS a list of public keys which will be able to decrypt the data (only the current key here but additional ones could be added)
SOPS_AGE_RECIPIENTS=age1px36dnru88xffdnejh2ps0grsz9cygx05f8wa8ly47duxm7lyq4ql3rxcm

# Encrypt the secrets.yaml file
sops encrypt secrets.yaml
```

Once encrypted the content of the *secrets.yaml* file is modified as follows:

```bash
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

- Helmfile

We can now reference the *secrets.yaml* file in the Helmfile definition of an application as follows:

Note: Helmfile tries to decrypt the content of properties in files defined under the *secrets* property of a release

```yaml
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

As the `age` key is given to the Argo CD's Helmfile plugin, each time the above application needs to be deployed / updated the plugin will be able to use this key to decrypt the properties first.

Note: `age` is one of the encryption method that is supported by SOPS (and thus by Helmfile). Other encryption methods exist, but they are not taken into account in this plugin.

## Status

This is currently a work in progress. Feel free to give it a try and provide feedback :)

## License

MIT License

Copyright (c) [2025]

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

