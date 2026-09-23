#!/bin/bash
export AWS_PAGER=""

CLUSTER=cluster
NODEGROUP=udacity
REGION=us-east-1

echo "=== 1. NODE GROUP FULL DETAILS ==="
aws eks describe-nodegroup \
  --cluster-name $CLUSTER \
  --nodegroup-name $NODEGROUP \
  --region $REGION \
  --query 'nodegroup.{Status:status,AmiType:amiType,InstanceTypes:instanceTypes,Health:health.issues,Scaling:scalingConfig}' \
  --output json

echo ""
echo "=== 2. AUTO SCALING GROUP ACTIVITIES ==="
ASG=$(aws eks describe-nodegroup \
  --cluster-name $CLUSTER \
  --nodegroup-name $NODEGROUP \
  --region $REGION \
  --query 'nodegroup.resources.autoScalingGroups[0].name' \
  --output text 2>/dev/null)

echo "ASG Name: $ASG"
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name $ASG \
  --max-items 5 \
  --region $REGION \
  --query 'Activities[].{Status:StatusCode,Description:Description,Cause:Cause}' \
  --output json

echo ""
echo "=== 3. EC2 INSTANCES ==="
aws ec2 describe-instances \
  --filters "Name=tag:eks:nodegroup-name,Values=$NODEGROUP" \
  --region $REGION \
  --query "Reservations[].Instances[].{ID:InstanceId,State:State.Name,Type:InstanceType}" \
  --output table

echo ""
echo "=== 4. AWS-AUTH CONFIGMAP ==="
kubectl get configmap aws-auth -n kube-system -o yaml 2>&1