## Server-side Swift development using an AWS CI/CD pipeline

This project is augmented from a great sample here: https://aws.amazon.com/blogs/opensource/continuous-delivery-server-side-swift-aws. 

The goal of the augumentation is to deploy Vapor to AWS with a single script command.

## Getting started
 
 1. Ensure you have AWS CLI installed and default credentials setup.
 2. Edit the bucket name in tools.sh to something unique. This bucket will be created and deleted upon stack creation/deletion.
 2. Run with `./tools.sh setupAll <dockerhub username> <dockerhub password>`
 3. Wait 20+ minutes for stack to create.
 4. Run `./tools.sh openSite` to open your site.
