#!/bin/bash
export AWS_PAGER=""

CLUSTER=cluster
NODEGROUP=udacity
REGION=us-east-1

echo "==============================================="
echo " EKS DIAGNOSTIC REPORT"
echo "==============================================="
echo ""

echo "=== 1. NODE GROUP LIST ==="
aws eks list-nodegroups --cluster-name $CLUSTER --region $REGION
echo ""

echo "=== 2. NODE GROUP STATUS & HEALTH ==="
aws eks describe-nodegroup \
  --cluster-name $CLUSTER \
  --nodegroup-name $NODEGROUP \
  --region $REGION \
  --query 'nodegroup.{Status:status,CapacityType:capacityType,AmiType:amiType,InstanceTypes:instanceTypes,Health:health.issues,Scaling:scalingConfig}' \
  --output json
echo ""

echo "=== 3. EC2 INSTANCES IN THE NODE GROUP ==="
aws ec2 describe-instances \
  --filters "Name=tag:eks:nodegroup-name,Values=$NODEGROUP" \
  --region $REGION \
  --query "Reservations[].Instances[].{ID:InstanceId,State:State.Name,Type:InstanceType,AZ:Placement.AvailabilityZone,PrivateIP:PrivateIpAddress}" \
  --output table
echo ""

echo "=== 4. AUTO SCALING GROUP SCALING ACTIVITIES ==="
ASG=$(aws eks describe-nodegroup \
  --cluster-name $CLUSTER \
  --nodegroup-name $NODEGROUP \
  --region $REGION \
  --query 'nodegroup.resources.autoScalingGroups[0].name' \
  --output text 2>/dev/null)

if [ -n "$ASG" ] && [ "$ASG" != "None" ]; then
  echo "ASG name: $ASG"
  aws autoscaling describe-scaling-activities \
    --auto-scaling-group-name $ASG \
    --max-items 5 \
    --region $REGION \
    --query 'Activities[].{Status:StatusCode,Description:Description,Cause:Cause}' \
    --output table
else
  echo "No Auto Scaling Group found for node group '$NODEGROUP'."
fi
echo ""

echo "=== 5. TERRAFORM STATE (EKS RESOURCES) ==="
cd /workspace/setup/terraform 2>/dev/null && \
  terraform state list 2>/dev/null | grep -E "node_group|eks_cluster"
echo ""

echo "=== 6. KUBECTL NODES ==="
kubectl get nodes 2>&1
echo ""

echo "==============================================="
echo " END OF REPORT"
echo "==============================================="