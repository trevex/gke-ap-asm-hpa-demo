# GKE Autopilot with ASM illustrating HPA 


## Prerequisites
```
terraform
gcloud
kubectl
```

Create a project and pick a region and export them for the following code snippets, e.g.:
```bash
export PROJECT="nvoss-gke-ap-asm-hpa-demo"
export REGION="europe-west4"
```

## Bucket for terraform state

```bash
gsutil mb -p ${PROJECT} -l ${REGION} -b on gs://${PROJECT}-tf-state
gsutil versioning set on gs://${PROJECT}-tf-state
# Make sure terraform is able to use your credentials (only required if not already the case)
gcloud auth application-default login --project ${PROJECT}-shared
```

## Update terraform code

You'll have to update references to the Google Cloud project and region as well as newly created bucket in these files:
```bash
0-cluster/cluster.auto.tfvars
0-cluster/main.tf # backend config at top of file
```

## Create the cluster

```bash
terraform -chdir=0-cluster init
terraform -chdir=0-cluster apply
```

### Check if ASM is ready

```bash
gcloud container fleet mesh describe --project ${PROJECT}
```

### Connect to the cluster

```bash
gcloud container clusters get-credentials mycluster --region ${REGION} --project ${PROJECT}
```

## Setup Stackdriver adapter

```bash
kubectl apply -f 1-stackdriver-adapter/
```

We have Workload Identity enabled so we need to give the adapter permissions to access monitoring explicitly:
```bash
gcloud iam service-accounts create stackdriver-adapter --project=${PROJECT}
gcloud projects add-iam-policy-binding ${PROJECT} \
  --member "serviceAccount:stackdriver-adapter@${PROJECT}.iam.gserviceaccount.com" \
  --role "roles/monitoring.viewer"
gcloud iam service-accounts add-iam-policy-binding stackdriver-adapter@${PROJECT}.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:${PROJECT}.svc.id.goog[custom-metrics/custom-metrics-stackdriver-adapter]" \
  --project ${PROJECT}
kubectl annotate serviceaccount --namespace custom-metrics \
  custom-metrics-stackdriver-adapter \
  iam.gke.io/gcp-service-account=stackdriver-adapter@${PROJECT}.iam.gserviceaccount.com
```

## Setup Istio-Gateway and Services

```bash
kubectl apply -f 2-ingress-gateway/
kubectl apply -f 3-services/
```

## Notes

```bash
kubectl get --raw https://KUBE-APISERVER-IP:6443/apis/custom.metrics.k8s.io/v1beta1 | jq | grep istio
```

Metric kinds: https://github.com/GoogleCloudPlatform/k8s-stackdriver/tree/master/custom-metrics-stackdriver-adapter#metric-kinds

Starting point for terraform setup (`0-cluster`): https://cloud.google.com/service-mesh/docs/unified-install/install-anthos-service-mesh-command

