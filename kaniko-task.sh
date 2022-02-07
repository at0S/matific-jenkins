export APP_REPO=$(aws ecr create-repository \
 --repository-name matific-app \
 --query 'repository.repositoryUri' --region ap-southeast-2 --profile ifm-examples --output text)
export APP_IMAGE="${APP_REPO}:latest"

# Create an Amazon CloudWatch Log Group to Store Log Output
aws logs create-log-group \
  --log-group-name kaniko-builder --profile ifm-examples --region ap-southeast-2

# Export the AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --profile ifm-examples --region ap-southeast-2 \
  --query 'Account' \
  --output text)

# Create the ECS Task Definition.
cat << EOF > ecs-task-defintion.json
{
    "family": "kaniko",
    "taskRoleArn": "kaniko_ecs_role",
    "executionRoleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/ecsTaskExecutionRole",
    "networkMode": "awsvpc",
    "containerDefinitions": [
        {
            "name": "kaniko",
            "image": "172173733067.dkr.ecr.ap-southeast-2.amazonaws.com/kaniko-builder:executor",
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "kaniko-builder",
                    "awslogs-region": "ap-southeast-2",
                    "awslogs-stream-prefix": "kaniko"
                }
            },
            "command": [
                "--context", "git://github.com/at0S/django-realworld-example-app.git",
                "--dockerfile", "Dockerfile",
                "--destination", "$APP_IMAGE",
                "--force"
            ]
        }],
    "requiresCompatibilities": ["FARGATE"],
    "cpu": "512",
    "memory": "1024"
}
EOF

aws ecs register-task-definition \
  --cli-input-json file://ecs-task-defintion.json --profile ifm-examples --region ap-southeast-2
