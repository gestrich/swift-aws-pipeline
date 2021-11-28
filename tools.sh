#!/bin/bash


##You must at least edit the BUCKET_NAME to your own.
BUCKET_NAME=org.gestrich.codebuild
REGION_NAME="us-east-1"
STACK_NAME="swift-build"
REPO_NAME="codebuild/swift"
APP_REPO_PATH=sample-vapor-app

function setupAll() {
  if [ "$#" -ne 2 ]; then
    echo "Call with params <dockerHubUsername> <dockerHubPassword>"
    exit 1
  fi
  dockerHubUsername="$1"
  dockerHubPassword="$2"

  echo "**PHASE** Creating Stack"
  createStack
  echo "**PHASE** Pushing Codebuild Image"
  pushCodeBuildImage
  echo "**PHASE** Updating Docker Credentials"
  updateDockerHubSecrets $dockerHubUsername $dockerHubPassword
  echo "**PHASE** Pushing Vapor app code"
  pushAppCodeRepo
  echo "**PHASE** Updating the Stack"
  echo "This will take a bit as CodePipeline needs to generate an image"
  updateStack
}

function createStack {
  aws s3api create-bucket --bucket $BUCKET_NAME --region $REGION_NAME
  CF_BUCKET=$BUCKET_NAME ./scripts/create-stack.sh
  aws cloudformation wait stack-create-complete --stack-name $STACK_NAME 
}

function updateStack {
  CF_BUCKET=$BUCKET_NAME ./scripts/update-stack.sh
  aws cloudformation wait stack-update-complete --stack-name $STACK_NAME 
}

function deleteStack {
  aws s3 rm s3://$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='S3ArtifactBucket'].OutputValue" --output text)/ --recursive
  IMAGES_TO_DELETE=$(aws ecr list-images --repository-name $REPO_NAME --query 'imageIds[*]' --output json)
  aws ecr batch-delete-image --repository-name $REPO_NAME --image-ids "$IMAGES_TO_DELETE"
  IMAGES_TO_DELETE=$(aws ecr list-images --repository-name swift-app --query 'imageIds[*]' --output json)
  aws ecr batch-delete-image --repository-name swift-app --image-ids "$IMAGES_TO_DELETE"

  aws cloudformation delete-stack --stack-name $STACK_NAME
  aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME
  
  aws s3 rm s3://$BUCKET_NAME --recursive; 
  aws s3api delete-bucket --bucket $BUCKET_NAME --region $REGION_NAME;
}

function pushCodeBuildImage(){

  #Manually can do this too in: AWS Console: ECR -> codebuild/swift -> View push commands -> Follow the instructions

  TAG_NAME=latest

  cd codebuild-image
  ACCOUNT_ID="$(aws sts get-caller-identity | jq -r .Account)";
  aws ecr get-login-password --region $REGION_NAME | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION_NAME.amazonaws.com
  docker build -t $REPO_NAME .
  docker tag $REPO_NAME:latest $ACCOUNT_ID.dkr.ecr.$REGION_NAME.amazonaws.com/$REPO_NAME:$TAG_NAME
  echo "pushing"
  docker push $ACCOUNT_ID.dkr.ecr.$REGION_NAME.amazonaws.com/$REPO_NAME:$TAG_NAME
  cd ..
}

function pushAppCodeRepo(){

  cd $APP_REPO_PATH
  repo_name="$(aws codecommit list-repositories | jq -r '.repositories[] | select(.repositoryName | startswith("swift-build-Pipeline")) | .repositoryName')";
  url="$(aws codecommit get-repository   --repository-name $repo_name | jq -r '.repositoryMetadata.cloneUrlHttp')"
  git remote set-url aws  $url
  git push --force --set-upstream aws master
  cd ..

  #Manually can get URL too from AWS Console:
    #CodeCommit  -> swift-build-Pipleline-* -> Clone URL -> Clone HTTPS (will copy a url to clipboard)

  #To Create a new version of the Vapor Hello World App
    #vapor new hello -n
    #cd hello
    #Copy in these files from prior apps
      #	appspec.yml
      #	buildspec*
      #	imagedefinitions.json*
      #	scripts/

}

function updateDockerHubSecrets(){
  if [ "$#" -ne 2 ]; then
    echo "Call with params <dockerHubUsername> <dockerHubPassword>"
    exit 1
  fi
  dockerHubUsername="$1"
  dockerHubPassword="$2"
  updateEnviromentVariable DOCKER_HUB_USERNAME $dockerHubUsername 
  updateEnviromentVariable DOCKER_HUB_PASSWORD $dockerHubPassword 
}

function updateEnviromentVariable(){
  if [ "$#" -ne 2 ]; then
    echo "Call with params <envVarName> <envVarValue>"
    exit 1
  fi
  ENV_VAR_NAME="$1"
  ENV_VAR_VALUE="$2"
  json_file_name="temp_file.json"
  codeBuildName="$(aws codebuild list-projects | jq -r '.projects[] | select( startswith("swift-build-Pipeline") ) | select( endswith("ContainerBuild") )')"
  aws codebuild update-project --name $codeBuildName | jq .project.environment > $json_file_name 
  cat $json_file_name | jq --arg ENV_VAR_NAME "$ENV_VAR_NAME" "del(.environmentVariables[] | select(.\"name\" == \"$ENV_VAR_NAME\") )" > tmp.json && mv tmp.json $json_file_name 
  cat $json_file_name | jq --arg ENV_VAR_NAME "$ENV_VAR_NAME" --arg ENV_VAR_VALUE "$ENV_VAR_VALUE" ".environmentVariables += [{\"name\":\"$ENV_VAR_NAME\", \"value\":\"$ENV_VAR_VALUE\", \"type\": \"PLAINTEXT\" }]" > tmp.json && mv tmp.json $json_file_name
  aws codebuild update-project --name $codeBuildName --environment "$(cat $json_file_name)";
  rm $json_file_name
}

function openSite {
  open $(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='EcsLbUrl'].OutputValue" --output text)
}

# Check if the function exists (bash specific)
if [ $# -gt 0 ]; then
#if declare -f "$1" > /dev/null
  # call arguments verbatim
  "$@"
else
  # Show a helpful error
  echo "Run again, followed by function name:\n"
  typeset -f | awk '!/^main[ (]/ && /^[^ {}]+ *\(\)/ { gsub(/[()]/, "", $1); print $1}'
  exit 1
fi
