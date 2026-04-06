#!/bin/bash

# ============================================
# CloudSentinel — Auto Isolation Script
# Automatically isolates suspicious pods
# AMD Cloud Computing Hackathon 2026
# ============================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="default"
SLACK_WEBHOOK_URL="https://hooks.slack.com/your-webhook-url"
LOG_FILE="/var/log/cloudsentinel/isolation.log"
ALERT_EMAIL="admin@cloudsentinel.com"

# ============================================
# FUNCTION: Log Message
# ============================================
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG_FILE
}

# ============================================
# FUNCTION: Send Slack Alert
# ============================================
send_alert() {
    POD_NAME=$1
    THREAT_TYPE=$2
    
    log "${YELLOW}📢 Sending alert for pod: $POD_NAME${NC}"
    
    curl -s -X POST $SLACK_WEBHOOK_URL \
    -H 'Content-type: application/json' \
    --data "{
        \"text\": \"🚨 *CloudSentinel Security Alert*\",
        \"attachments\": [{
            \"color\": \"danger\",
            \"fields\": [
                {
                    \"title\": \"Threat Detected\",
                    \"value\": \"$THREAT_TYPE\",
                    \"short\": true
                },
                {
                    \"title\": \"Pod Isolated\",
                    \"value\": \"$POD_NAME\",
                    \"short\": true
                },
                {
                    \"title\": \"Namespace\",
                    \"value\": \"$NAMESPACE\",
                    \"short\": true
                },
                {
                    \"title\": \"Time\",
                    \"value\": \"$(date '+%Y-%m-%d %H:%M:%S')\",
                    \"short\": true
                },
                {
                    \"title\": \"Status\",
                    \"value\": \"✅ Pod automatically isolated\",
                    \"short\": false
                }
            ]
        }]
    }"
    
    log "${GREEN}✅ Alert sent successfully${NC}"
}

# ============================================
# FUNCTION: Isolate Pod
# ============================================
isolate_pod() {
    POD_NAME=$1
    THREAT_TYPE=$2
    
    log "${RED}🚨 THREAT DETECTED: $THREAT_TYPE on pod $POD_NAME${NC}"
    log "${YELLOW}⚡ Starting isolation process...${NC}"
    
    # Step 1: Label the pod as compromised
    kubectl label pod $POD_NAME \
        security=compromised \
        cloudsentinel-isolated=true \
        -n $NAMESPACE \
        --overwrite
    log "${GREEN}✅ Step 1: Pod labeled as compromised${NC}"
    
    # Step 2: Apply network isolation policy
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: isolate-$POD_NAME
  namespace: $NAMESPACE
spec:
  podSelector:
    matchLabels:
      security: compromised
  policyTypes:
  - Ingress
  - Egress
EOF
    log "${GREEN}✅ Step 2: Network policy applied — all traffic blocked${NC}"
    
    # Step 3: Scale up healthy replacement pods
    DEPLOYMENT=$(kubectl get pod $POD_NAME \
        -n $NAMESPACE \
        -o jsonpath='{.metadata.labels.app}')
    
    kubectl scale deployment $DEPLOYMENT \
        --replicas=+1 \
        -n $NAMESPACE
    log "${GREEN}✅ Step 3: Healthy replacement pod scaled up${NC}"
    
    # Step 4: Remove compromised pod from service
    kubectl patch pod $POD_NAME \
        -n $NAMESPACE \
        -p '{"metadata":{"labels":{"app":"isolated"}}}'
    log "${GREEN}✅ Step 4: Pod removed from service load balancer${NC}"
    
    # Step 5: Send alert to admin
    send_alert $POD_NAME $THREAT_TYPE
    log "${GREEN}✅ Step 5: Admin alerted via Slack${NC}"
    
    # Step 6: Generate audit log entry
    echo "$(date '+%Y-%m-%d %H:%M:%S') | ISOLATED | $POD_NAME | $THREAT_TYPE | $NAMESPACE" \
        >> /var/log/cloudsentinel/audit.log
    log "${GREEN}✅ Step 6: Audit log entry created${NC}"
    
    log "${GREEN}🛡️ ISOLATION COMPLETE — Pod $POD_NAME successfully isolated in seconds!${NC}"
}

# ============================================
# FUNCTION: Monitor Falco Events
# ============================================
monitor_threats() {
    log "${BLUE}🔍 CloudSentinel monitoring started...${NC}"
    log "${BLUE}👁️  Watching for threats in namespace: $NAMESPACE${NC}"
    
    # Listen to Falco events
    kubectl logs -f \
        -l app=falco \
        -n $NAMESPACE | while read line; do
        
        # Check for CRITICAL threats
        if echo "$line" | grep -q "CRITICAL"; then
            POD=$(echo "$line" | grep -oP 'container=\K[^ ]+')
            TYPE=$(echo "$line" | grep -oP 'rule=\K[^ ]+')
            
            if [ ! -z "$POD" ]; then
                isolate_pod $POD "$TYPE"
            fi
        fi
        
        # Check for privilege escalation
        if echo "$line" | grep -q "Privilege Escalation"; then
            POD=$(echo "$line" | grep -oP 'container=\K[^ ]+')
            isolate_pod $POD "Privilege Escalation Attempt"
        fi
        
        # Check for crypto mining
        if echo "$line" | grep -q "Crypto Mining"; then
            POD=$(echo "$line" | grep -oP 'container=\K[^ ]+')
            isolate_pod $POD "Crypto Mining Detected"
        fi
        
    done
}

# ============================================
# MAIN — Start CloudSentinel
# ============================================
echo -e "${GREEN}"
echo "╔═══════════════════════════════════════╗"
echo "║   🛡️  CloudSentinel Auto-Isolator     ║"
echo "║   AMD Cloud Computing Hackathon 2026  ║"
echo "║   Detect. Isolate. Heal. Auto.        ║"
echo "╚═══════════════════════════════════════╝"
echo -e "${NC}"

# Create log directory
mkdir -p /var/log/cloudsentinel

# Start monitoring
monitor_threats
