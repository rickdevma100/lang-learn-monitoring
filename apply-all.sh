#!/bin/bash
# apply-all.sh — Deploy the complete lang-learn monitoring stack.
#
# Run this from the lang-learn-monitoring/ directory:
#   chmod +x apply-all.sh
#   ./apply-all.sh
#
# Prerequisites:
#   - MicroK8s running with kube-prometheus-stack (release name: monitoring)
#   - lang-learn namespace exists
#   - lang-learn-prompt-optimizer pod is running
#   - Gmail App Password ready (https://myaccount.google.com/apppasswords)

set -euo pipefail

KUBECTL="microk8s kubectl"
NAMESPACE="lang-learn"

echo "================================================================"
echo " Lang-Learn Monitoring Stack Deployment"
echo "================================================================"

# 1. Create SMTP secret (prompts for password if not already set)
if ! $KUBECTL get secret alertmanager-smtp-secret -n "$NAMESPACE" &>/dev/null; then
    echo ""
    echo "Step 1/5: Create Gmail SMTP secret"
    echo "  Generate an App Password at: https://myaccount.google.com/apppasswords"
    read -rsp "  Enter Gmail App Password: " SMTP_PASS
    echo ""
    $KUBECTL create secret generic alertmanager-smtp-secret \
        --from-literal=smtp-password="$SMTP_PASS" \
        -n "$NAMESPACE"
    echo "  ✅ Secret created"
else
    echo "Step 1/5: SMTP secret already exists — skipping"
fi

# 2. Apply ServiceMonitor (Prometheus scraping)
echo ""
echo "Step 2/5: Apply ServiceMonitor (Prometheus scraping every 15s)"
$KUBECTL apply -f manifests/servicemonitor.yaml
echo "  ✅ ServiceMonitor applied"

# 3. Apply PrometheusRules (alert definitions)
echo ""
echo "Step 3/5: Apply PrometheusRules (alert conditions)"
$KUBECTL apply -f manifests/prometheus-rules.yaml
echo "  ✅ PrometheusRules applied"

# 4. Apply AlertmanagerConfig (routing: webhook + email)
echo ""
echo "Step 4/5: Apply AlertmanagerConfig (routing to optimizer + email)"
$KUBECTL apply -f manifests/alertmanager-config.yaml
echo "  ✅ AlertmanagerConfig applied"

# 5. Apply Grafana dashboards
echo ""
echo "Step 5/5: Apply Grafana dashboards ConfigMap"
$KUBECTL apply -f manifests/grafana-dashboards-configmap.yaml
echo "  ✅ Grafana dashboards applied"

# Summary
echo ""
echo "================================================================"
echo " Deployment complete. Verifying resources..."
echo "================================================================"
echo ""
echo "ServiceMonitor:"
$KUBECTL get servicemonitor -n "$NAMESPACE"
echo ""
echo "PrometheusRules:"
$KUBECTL get prometheusrule -n "$NAMESPACE"
echo ""
echo "AlertmanagerConfig:"
$KUBECTL get alertmanagerconfig -n "$NAMESPACE"
echo ""
echo "================================================================"
echo " Next steps:"
echo "   1. Check Prometheus targets (port-forward 9090):"
echo "      microk8s kubectl port-forward svc/prometheus-operated 9090 -n monitoring"
echo "      Open: http://localhost:9090/targets"
echo ""
echo "   2. Check Alertmanager config was merged:"
echo "      microk8s kubectl port-forward svc/alertmanager-operated 9093 -n monitoring"
echo "      Open: http://localhost:9093/#/status"
echo ""
echo "   3. Simulate a firing alert to test the full loop:"
echo "      curl -X POST http://localhost:8000/webhook -H 'Content-Type: application/json' \\"
echo "        -d '{\"receiver\":\"prompt-optimizer\",\"status\":\"firing\","
echo "            \"alerts\":[{\"status\":\"firing\",\"labels\":{\"alertname\":\"CEFRPromptDegraded\","
echo "            \"action\":\"optimize_prompt\",\"severity\":\"warning\"}}],"
echo "            \"groupLabels\":{\"alertname\":\"CEFRPromptDegraded\"},"
echo "            \"commonLabels\":{\"action\":\"optimize_prompt\"}}'"
echo "================================================================"
