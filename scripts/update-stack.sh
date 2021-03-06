aws cloudformation package --template-file ./templates/main.yml --s3-bucket $CF_BUCKET --output-template-file packaged-template.yml
aws cloudformation update-stack --cli-input-json file://create-stack.json --template-body file://./packaged-template.yml --parameters ParameterKey=ECSDesiredCount,ParameterValue=1
