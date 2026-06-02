# lang-learn-monitoring

Standalone Kubernetes manifests for the Lang-Learn MLOps feedback loop.
Applies independently — no Helm required.

---

## Complete Alert → Optimizer Flow

```
KServe inference pod
  │  exposes /metrics  (prometheus_client)
  ▼
ServiceMonitor              ← tells Prometheus WHERE to scrape
  │  scrapes /metrics every 15s
  ▼
Prometheus
  │  evaluates PrometheusRules every 1m
  ▼
PrometheusRule              ← defines WHEN to fire
  │  e.g. avg(lang_learn_cefr_match_score) < 0.75 for 15m
  ▼
Alertmanager
  │  reads AlertmanagerConfig ← defines WHERE to send
  ├──▶  POST /webhook  →  lang-learn-prompt-optimizer pod
  │                           │
  │                           ▼
  │                       Run 4 prompt candidates via HTTP
  │                       Score with A1/B2 analysis
  │                       Pick winner (if Δ ≥ 0.02)
  │                       Archive old prompt
  │                       Write new prompt
  │                           │
  │                           ▼
  └──▶  Email             HTML report → rickdev.ma100@gmail.com
        rickdev.ma100@gmail.com
```

---

## Files

| File | Purpose |
|------|---------|
| `manifests/servicemonitor.yaml` | Prometheus scrapes `/metrics` from inference pod every 15s |
| `manifests/prometheus-rules.yaml` | 6 alert rules (3 trigger optimizer, 3 are infra-only) |
| `manifests/alertmanager-config.yaml` | Routes `action=optimize_prompt` alerts → webhook + email |
| `manifests/alertmanager-smtp-secret.yaml` | Template for Gmail SMTP credentials |
| `manifests/grafana-dashboards-configmap.yaml` | Auto-loads 2 Grafana dashboards |
| `dashboards/lang-learn-overview.json` | Dashboard 1 — Request rate, CEFR score, latency, errors |
| `dashboards/lang-learn-cefr-quality.json` | Dashboard 2 — CEFR heatmap, per-level breakdown, feedback |
| `apply-all.sh` | One-shot deploy script |

---

## Alerts Defined

### Prompt Quality (trigger optimizer)

| Alert | Condition | For | Action |
|-------|-----------|-----|--------|
| `CEFRPromptDegraded` | `avg(lang_learn_cefr_match_score) < 0.75` | 15m | POST /webhook |
| `CEFRMismatchRateHigh` | mismatch rate > 20% | 15m | POST /webhook |
| `UserFeedbackNegative` | downvotes > upvotes | 30m | POST /webhook |

### Infrastructure (email only)

| Alert | Condition | For |
|-------|-----------|-----|
| `InferenceHighLatency` | p99 latency > 30s | 5m |
| `InferenceErrorRateHigh` | error rate > 10% | 5m |
| `InferenceModelNotLoaded` | `lang_learn_model_loaded == 0` | 2m |

---

## Deploy

```bash
# One command deploys everything
chmod +x apply-all.sh
./apply-all.sh
```

Or apply manifests individually:

```bash
# 1. SMTP secret (do this first, required for email)
microk8s kubectl create secret generic alertmanager-smtp-secret \
  --from-literal=smtp-password='YOUR_GMAIL_APP_PASSWORD' \
  -n lang-learn

# 2. Prometheus scraping
microk8s kubectl apply -f manifests/servicemonitor.yaml

# 3. Alert rules
microk8s kubectl apply -f manifests/prometheus-rules.yaml

# 4. Alertmanager routing
microk8s kubectl apply -f manifests/alertmanager-config.yaml

# 5. Grafana dashboards
microk8s kubectl apply -f manifests/grafana-dashboards-configmap.yaml
```

---

## Verify

### Check Prometheus is scraping
```bash
microk8s kubectl port-forward svc/prometheus-operated 9090 -n monitoring
# Open http://localhost:9090/targets → look for "lang-learn-inference"
```

### Check alert rules loaded
```bash
# In Prometheus UI: http://localhost:9090/rules
# OR:
microk8s kubectl get prometheusrule -n lang-learn
```

### Check Alertmanager routing
```bash
microk8s kubectl port-forward svc/alertmanager-operated 9093 -n monitoring
# Open http://localhost:9093/#/status → look for lang-learn config section
```

### Simulate a firing alert (end-to-end test)
```bash
# Port-forward the optimizer service first:
microk8s kubectl port-forward svc/lang-learn-prompt-optimizer 8000 -n lang-learn

# Fire a test alert:
curl -X POST http://localhost:8000/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "receiver": "prompt-optimizer",
    "status": "firing",
    "alerts": [{
      "status": "firing",
      "labels": {
        "alertname": "CEFRPromptDegraded",
        "action": "optimize_prompt",
        "severity": "warning",
        "language": "German",
        "level": "A2"
      },
      "annotations": {
        "summary": "Prompt quality degraded",
        "description": "CEFR score below 0.75"
      }
    }],
    "groupLabels": {"alertname": "CEFRPromptDegraded"},
    "commonLabels": {"action": "optimize_prompt"}
  }'

# Poll the result:
curl http://localhost:8000/jobs/latest/info | python3 -m json.tool
```

---

## Gmail App Password Setup

The SMTP secret uses a Gmail **App Password** (not your normal password).

1. Go to: https://myaccount.google.com/apppasswords
2. Create an App Password for "Mail"
3. Run:
   ```bash
   microk8s kubectl create secret generic alertmanager-smtp-secret \
     --from-literal=smtp-password='YOUR_16_CHAR_APP_PASSWORD' \
     -n lang-learn
   ```

> **Important:** Do not commit the real password to git. The `alertmanager-smtp-secret.yaml` file is a template only.
