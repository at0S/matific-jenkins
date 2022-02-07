# Create a trust policy
cat << EOF > ecs-trust-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "ecs-tasks.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  }
EOF
 
# Create an IAM policy
cat << EOF > iam-role-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecr:GetAuthorizationToken",
                "ecr:InitiateLayerUpload",
                "ecr:UploadLayerPart",
                "ecr:CompleteLayerUpload",
                "ecr:PutImage",
                "ecr:BatchGetImage",
                "ecr:BatchCheckLayerAvailability"
            ],
            "Resource": "*"
        }
    ]
}
EOF
 
# Create an IAM role
ECS_TASK_ROLE=$(aws iam create-role \
  --role-name kaniko_ecs_role \
  --assume-role-policy-document file://ecs-trust-policy.json \
  --query 'Role.Arn' --profile ifm-examples --output text)
 
aws iam put-role-policy \
 --role-name kaniko_ecs_role \
 --policy-name kaniko_push_policy \
 --policy-document file://iam-role-policy.json --profile ifm-examples
