## Jenkins high level design document

I plan to host Jenkins control plane (e.g Jenkins UI/Controller) on ECS Fargate. Its reasonably flexible runtime with no need to manage lots and lots of things. 

## Goals
 - Must be able to communicate with GitHub to fetch sources
 - Must be able to bootstrap a build agent in same environment  - retrospecively, I moved this to non-goal
 - Must provide secure access (eg. https://jenkins.examples.ifm.tools)

### Non goals:
 - Privacy on environment
 - Optimized build jobs
 - Jenkins HA and update functionality
 - Observability

## Implementation
Do we have an official Jenkins docker image?
They answer is -  yes! And we probably should make a mental note to check if there is an official helm chart for it too.
I don’t really want to dive much into the underlying design and using just a so-called default style VPC, with VPC covering the range of 172.16.0.0 in ap-southeast-2 with 2 subnets in 172.16.0.0 and 172.16.1.0 and routing out directly via Internet Gateway. This is not “normal” for me, and we can experience certain hiccups creating the service.
I’m creating the task definition via the UI, just to save some time from composing nicely looking CloudFormation or Terraform.  I think this is relatively new - the task defenition created via UI is also managed via CloudFormation and for the sake of brevity I’m dumping it’s output here
```json
{
  "AWSTemplateFormatVersion": "2010-09-09",
  "Description": "The template used to create an ECS Task definition from the ECS Console.",
  "Resources": {
    "ECSTaskDefinition": {
      "Type": "AWS::ECS::TaskDefinition",
      "Properties": {
        "ContainerDefinitions": [
          {
            "LogConfiguration": {
              "Options": {
                "awslogs-group": "/ecs/jenkins",
                "awslogs-region": "ap-southeast-2",
                "awslogs-stream-prefix": "ecs",
                "awslogs-create-group": "true"
              },
              "LogDriver": "awslogs"
            },
            "Name": "jenkins-master",
            "Image": "jenkins/jenkins:2.333",
            "Essential": true,
            "PortMappings": [
              {
                "ContainerPort": "8080",
                "Protocol": "tcp"
              }
            ],
            "Environment": [],
            "EnvironmentFiles": []
          }
        ],
        "Family": "jenkins",
        "RequiresCompatibilities": [
          "FARGATE"
        ],
        "NetworkMode": "awsvpc",
        "Cpu": ".5 vCPU",
        "Memory": "1 GB",
        "RuntimePlatform": {
          "CpuArchitecture": "X86_64",
          "OperatingSystemFamily": "LINUX"
        },
        "ExecutionRoleArn": "arn:aws:iam::172173733067:role/ecsTaskExecutionRole",
        "Tags": [
          {
            "Key": "ecs:taskDefinition:createdFrom",
            "Value": "ecs-console-v2"
          },
          {
            "Key": "ecs:taskDefinition:stackId",
            "Value": {
              "Ref": "AWS::StackId"
            }
          }
        ]
      }
    }
  },
  "Outputs": {
    "TaskDefinitionARN": {
      "Description": "The created task definition ARN.",
      "Value": {
        "Ref": "ECSTaskDefinition"
      }
    }
  }
}
```
For now, the task definition does not come with anything interesting though. Let’s run the container. We have to choose between “service” type workload and “task” type. The difference is in how ECS will treat the environment. Service is supposed to run for period of time and serve the incoming requests (and normally exists behind the load balancer, exposes ports and all that jazz). While “task” is suitable for a sort of batch processing, where the workload runs on some sort of schedule and apart from this schedule - it does not run ;)

The first hiccup here is that from the Networking settings section we can’t create a security group to allow inbound access on TCP:8080 (default for Jenkins), it supports only HTTP(80) and HTTPS(443). So to accomodate for our case, we need to settle a security group in EC2/VPC, let’s do that. 

Once SG is in place, we now can pick it up from the dropdown. Note: Service can support more than a single SG. We also assigning a public IP to our service.

Once service is running, we should set a DNS A record for our new service and follow up with configuration.  Going through the configuration, I arrived to the point being asked what is going to be Jenkins URL. I really want it to be a secure web service, hence it’s time to dive into the proxy setup in front of our container.

The first question is, can I use a specialised piece of software to front my service? Or do I need to have yet another task definition? 

I looked through the configuration and feel as if I want to simplify my setup, I’d better route requests into Jenkins master via the LoadBalancer. One of the limitations here is that all new instances of my service receive a new public IP address. That quickly becomes painful side hustle. To overcome that, let’s create an ALB.

While creating an ALB, we also need a TLS certificate. We can get one from the ACM (I’m picking the latest ELB policy, the one which uses only modern cipher suits, but still sadly with TLS1.2 support, why it is so hard for AWS create a good modern policy without known problems)

Next issue was the registration of the newly provisioned Jenkins with ALB. Default health check is expecting 200 status, but on the initial startup, Jenkins bombs the 403 and is expecting the admin password to be provided. I think 403 could be used as a successful health check, to cover this particular case. 

Spent some time on adding the Cloud configuration, there is couple of things I think deserve deeper involvement: plugin for ECS/Fargate is quite tedious to configure and is also looking for new maintainers. Of course the EC2 plugin is there… 

I’ve forked the https://github.com/at0S/django-realworld-example-app/ and want to make a build/deploy to happen here.
The plan is to use Build stage for producing the docker image and uploading it to DockerHub, Deploy step will create a task definition and run it as a service. So far I stuck in the pyenv & virtualenv setup and thinking to resort to building a Dockerfile for the app and proceed without clever environment setup.

Dockerfile is very simple, it produces runable image. Here is the file:

```
FROM python:3.5.2-alpine
RUN mkdir /app
COPY . /app
RUN addgroup -S matific && adduser -S matific -G matific && chown -R matific: /app
RUN pip install --no-cache-dir --upgrade pip
USER matific
WORKDIR /app
RUN pip install --user --no-cache-dir  -r requirements.txt
RUN python manage.py migrate
EXPOSE 5001
ENTRYPOINT ["python", "manage.py", "runserver", "0.0.0.0:5001"]
```
Now, the issue here is that we run our pipeline on Jenkins running on top of Fargate. Typically, it is possible to enable the container to build docker images, from within. Container must run in privileged mode and mount docker socket file. The problem, though, is twofold. Conceptually, it is bad idea to run special and very privileged containers. Secondly, Fargate just does not allow to do so. What we have though, is additional tooling to build container images in the user runtime, without privilege escalation. 

https://aws.amazon.com/blogs/containers/building-container-images-on-amazon-ecs-on-aws-fargate/
https://github.com/GoogleContainerTools/kaniko#how-does-kaniko-work

The flow for the builder is quite interesting. We need to instruct our build agent to create a task oriented  workload on top of Fargate. That makes sense, as build docker image is a workload with clear start and end, it is also hermetic. Looking at the example on AWS blog, I think it clearly needs better UX for developer (e.g script to codify all that, receiving source for the build on the input and providing a clear signal on the output, which we can then feed into another stage of the build or report or whatever).

The following part is mainly about creating the underlying infrastructure for kaniko, that’s out of scope of Pipeline configuration, keep that in mind. [See shell scripts in the root]
