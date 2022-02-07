KANIKO_VPC="vpc-069fca56d6976ddb7"
KANIKO_SUBNET="subnet-0ca166edb43a30a27"
# Create a security group for ECS task
KANIKO_SECURITY_GROUP=$(aws ec2 create-security-group \
  --description "SG for VPC Link" \
  --group-name "KANIKO_SG" \
  --vpc-id $KANIKO_VPC \
  --output text --region ap-southeast-2 --profile ifm-examples \
  --query 'GroupId')

# Start the ECS Task
cat << EOF > ecs-run-task.json
{
    "cluster": "exampleservices-cluster-v1",
    "count": 1,
    "launchType": "FARGATE",
    "networkConfiguration": {
        "awsvpcConfiguration": {
            "subnets": ["$KANIKO_SUBNET"],
            "securityGroups": ["$KANIKO_SECURITY_GROUP"],
            "assignPublicIp": "ENABLED"
        }
    },
    "platformVersion": "LATEST"
}
EOF

# Run the ECS Task using the "Run Task" command
aws ecs run-task \
    --task-definition kaniko:2 \
    --cli-input-json file://ecs-run-task.json --region ap-southeast-2 --profile ifm-examples
