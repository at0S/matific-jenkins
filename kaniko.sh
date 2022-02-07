# BUILD ENVIRONMENT
# AWS CLI, AWS SSO, Docker must be available, we don't explicitly check for that. Yet.
# Create a directory to store the container image artifacts

aws sso login
aws sts get-caller-identity --profile ifm-examples
# This is infra service
export KANIKO_BUILDER_REPO=$(aws ecr create-repository --repository-name kaniko-builder --query 'repository.repositoryUri' --region ap-southeast-2 --profile ifm-examples --output text)
export KANIKO_BUILDER_IMAGE="${KANIKO_BUILDER_REPO}:executor"


mkdir kaniko
cd kaniko

# Create the Container Image Dockerfle
cat << EOF > Dockerfile
FROM gcr.io/kaniko-project/executor:latest
COPY ./config.json /kaniko/.docker/config.json
EOF

# Create the Kaniko Config File for Registry Credentials
cat << EOF > config.json
{ "credsStore": "ecr-login" }
EOF

docker build --tag ${KANIKO_BUILDER_REPO}:executor .

aws ecr get-login-password --profile ifm-examples --region ap-southeast-2 | docker login \
   --username AWS \
   --password-stdin \
   $KANIKO_BUILDER_REPO

docker push ${KANIKO_BUILDER_REPO}:executor
