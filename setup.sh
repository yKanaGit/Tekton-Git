#!/bin/bash
set -e

# OpenShift Tekton CI/CD Setup Script

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}OpenShift Tekton CI/CD Setup${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if oc is installed
if ! command -v oc &> /dev/null; then
    echo -e "${RED}Error: oc CLI is not installed${NC}"
    exit 1
fi

# Check if logged in to OpenShift
if ! oc whoami &> /dev/null; then
    echo -e "${RED}Error: Not logged in to OpenShift cluster${NC}"
    echo -e "${YELLOW}Please run: oc login <cluster-url>${NC}"
    exit 1
fi

# Get current project/namespace
NAMESPACE=$(oc project -q)
echo -e "${GREEN}Current namespace: ${NAMESPACE}${NC}"
echo ""

# Ask for confirmation
read -p "Deploy to namespace '${NAMESPACE}'? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Deployment cancelled${NC}"
    exit 0
fi

echo -e "${GREEN}Step 1: Creating Tekton Tasks...${NC}"
oc apply -f tekton/tasks/git-clone.yaml
oc apply -f tekton/tasks/maven-build.yaml
oc apply -f tekton/tasks/buildah-push.yaml
oc apply -f tekton/tasks/deploy.yaml
echo -e "${GREEN}✓ Tasks created${NC}"
echo ""

echo -e "${GREEN}Step 2: Creating Pipeline...${NC}"
oc apply -f tekton/pipeline/build-deploy-pipeline.yaml
echo -e "${GREEN}✓ Pipeline created${NC}"
echo ""

echo -e "${GREEN}Step 3: Setting up Triggers...${NC}"

# Replace NAMESPACE placeholder in trigger-template
sed "s/NAMESPACE/${NAMESPACE}/g" tekton/triggers/trigger-template.yaml > /tmp/trigger-template-tmp.yaml
oc apply -f /tmp/trigger-template-tmp.yaml
rm /tmp/trigger-template-tmp.yaml

oc apply -f tekton/triggers/trigger-binding.yaml
oc apply -f tekton/triggers/event-listener.yaml
oc apply -f tekton/triggers/event-listener-route.yaml
echo -e "${GREEN}✓ Triggers created${NC}"
echo ""

echo -e "${GREEN}Step 4: Waiting for EventListener to be ready...${NC}"
sleep 5
WEBHOOK_URL=$(oc get route github-webhook -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [ -z "$WEBHOOK_URL" ]; then
    echo -e "${YELLOW}⚠ Route not yet available. Run this command later to get webhook URL:${NC}"
    echo -e "  oc get route github-webhook -o jsonpath='{.spec.host}'"
else
    echo -e "${GREEN}✓ Webhook URL: https://${WEBHOOK_URL}${NC}"
fi
echo ""

echo -e "${GREEN}Step 5: Configuring SecurityContextConstraints (SCC)...${NC}"
echo -e "${YELLOW}Note: This step requires cluster admin privileges${NC}"

# Try to add privileged SCC to pipeline serviceaccount
if oc adm policy add-scc-to-user privileged -z pipeline 2>/dev/null; then
    echo -e "${GREEN}✓ Privileged SCC granted to pipeline serviceaccount${NC}"
    SCC_CONFIGURED=true
else
    echo -e "${YELLOW}⚠ Could not configure SCC (requires admin privileges)${NC}"
    echo -e "${YELLOW}  Please run manually:${NC}"
    echo -e "  ${YELLOW}oc adm policy add-scc-to-user privileged -z pipeline${NC}"
    SCC_CONFIGURED=false
fi
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"

# Show SCC warning if not configured
if [ "$SCC_CONFIGURED" = false ]; then
    echo -e "${RED}⚠ IMPORTANT: Configure SCC before running pipelines!${NC}"
    echo -e "   ${YELLOW}oc adm policy add-scc-to-user privileged -z pipeline${NC}"
    echo -e "   ${YELLOW}Without this, buildah task will fail with 'PodAdmissionFailed' error${NC}"
    echo ""
fi

echo -e "1. Configure GitHub webhook:"
echo -e "   - Go to your GitHub repository > Settings > Webhooks"
echo -e "   - Payload URL: https://${WEBHOOK_URL}"
echo -e "   - Content type: application/json"
echo -e "   - Events: Just the push event"
echo ""
echo -e "2. Test the pipeline manually:"
echo -e "   ${YELLOW}oc create -f - <<EOF"
echo -e "   apiVersion: tekton.dev/v1beta1"
echo -e "   kind: PipelineRun"
echo -e "   metadata:"
echo -e "     generateName: build-deploy-run-"
echo -e "   spec:"
echo -e "     pipelineRef:"
echo -e "       name: build-deploy-pipeline"
echo -e "     params:"
echo -e "     - name: git-url"
echo -e "       value: https://github.com/YOUR_USERNAME/YOUR_REPO.git"
echo -e "     - name: git-revision"
echo -e "       value: main"
echo -e "     - name: image-name"
echo -e "       value: image-registry.openshift-image-registry.svc:5000/${NAMESPACE}/quarkus-demo"
echo -e "     - name: image-tag"
echo -e "       value: test-$(date +%s)"
echo -e "     - name: namespace"
echo -e "       value: ${NAMESPACE}"
echo -e "     workspaces:"
echo -e "     - name: shared-workspace"
echo -e "       volumeClaimTemplate:"
echo -e "         spec:"
echo -e "           accessModes:"
echo -e "           - ReadWriteOnce"
echo -e "           resources:"
echo -e "             requests:"
echo -e "               storage: 1Gi"
echo -e "   EOF${NC}"
echo ""
echo -e "3. Watch pipeline execution:"
echo -e "   ${YELLOW}tkn pipelinerun list${NC}"
echo -e "   ${YELLOW}tkn pipelinerun logs -f <pipelinerun-name>${NC}"
echo ""
