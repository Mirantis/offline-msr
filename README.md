# offline-msr
Utilities for installing MSR offline

Execute the following command to run the utility:
`curl https://raw.githubusercontent.com/Mirantis/offline-msr/main/get-msr.sh > get-msr.sh && chmod +x get-msr.sh && ./get-msr.sh`

The most current images can be pulled using get-msr.sh utility
Here is an example output:
```
cert-manager-v1.7.2.tgz
msr-1.0.7.tgz
postgres-operator-1.7.1.tgz
msr-3.0.6.tar
```

TGZ files contain backed-up helm charts and TAR file has all images for MSR and all references for helm files

Use `docker load < msr-images-3.0.6.tar` to load these images elsewhere.
Helm charts are packaged as: cert-manager-v1.7.2.tgz, postgres-operator-1.7.1.tgz, msr-1.0.7.tgz
