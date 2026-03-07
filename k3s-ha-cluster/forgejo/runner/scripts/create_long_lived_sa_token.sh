NAMESPACE="forgejo"
SA_NAME="runner-forgejo-runner-sa"
APISERVER="https://kubernetes.default.svc"

# 1. Ask K8s to generate a permanent token Secret for your EXISTING ServiceAccount
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${SA_NAME}-long-lived-token
  namespace: ${NAMESPACE}
  annotations:
    kubernetes.io/service-account.name: ${SA_NAME}
type: kubernetes.io/service-account-token
EOF

# Wait a moment for K8s to populate the token data
sleep 2

# 2. Extract the Token and CA Certificate
TOKEN=$(kubectl get secret ${SA_NAME}-long-lived-token -n ${NAMESPACE} -o jsonpath='{.data.token}' | base64 --decode)
CA_CERT=$(kubectl get secret ${SA_NAME}-long-lived-token -n ${NAMESPACE} -o jsonpath='{.data.ca\.crt}')

# 3. Generate the Kubeconfig file
cat <<EOF > kubeconfig-ci.yaml
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${CA_CERT}
    server: ${APISERVER}
  name: in-cluster
contexts:
- context:
    cluster: in-cluster
    user: ${SA_NAME}
  name: ci-context
current-context: ci-context
users:
- name: ${SA_NAME}
  user:
    token: ${TOKEN}
EOF

echo "Done! Copy the contents of kubeconfig-ci.yaml to your Forgejo KUBECONFIG_DEPLOY Secret."
