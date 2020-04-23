---
date: "2019-08-19T00:00:00Z"
summary: How to store sensitive data like passwords within repo when using terraform.
  Simple solution for AWS users.
title: Storing secrets in terraform codebase with KMS
---

# Problem
Some terraform resources require passing sensitive data such as passwords and ssh keys.
When runing operation within a team, this quickly becomes a problem.
Git is a decentralized way of storing data and having your passwords in plaintext is a sub-optimal idea.
Even when using private git repositories, you still have passwords on each machine that has access to the repo.
The approach I suggest is tested within mid/big AWS environment.
It has some overhead, but I tried to reduce it to a minimum.

# KMS
[AWS KMS](https://aws.amazon.com/kms/) is conceptually a private key that is bound to IAM.
It is quite convinient in a lot use cases.
Here you can utilize it, to store sensitive data within terraform code.
You can provision your first KMS with [terraform as well](https://www.terraform.io/docs/providers/aws/r/kms_key.html).
Each KMS has it's own unique key id that you use to encrypt your secrets.

```shell
$ aws kms encrypt --key-id {KEY_ID} --plaintext {YOUR_SECRET} --output text --query CiphertextBlob

AQICANlZ[....]iqI75UTD9MqqkyzCrbkkQ==
```

The output is encrypted version of your secret that can be stored in git repository.

# KMS data provider

Once you know how to create KMS key and encrypt secrets, you can ingest them into other terraform resources.
To do, it use [aws_kms_secrets](https://www.terraform.io/docs/providers/aws/d/kms_secrets.html) data provider.
```terraform
data "aws_kms_secrets" "secrets" {
  secret {
        name = "master-password",
        payload = "AQECAHgaPa0J8WadplGCqqVAr4H...."
  }
}

master_password = "${data.aws_kms_secrets.secrets.plaintext["master-password"]}"
```

Data provider does the decryption.
You don't need to provide the key id because it is already a part of the encrypted text.
When calling terraform, provide AWS credentials that are allowed to decrypt given secret.
There is a [number of ways to do it](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html).
I recommend using `AWS_PROFILE` env variable as:
```
$ AWS_PROFILE=myprofile terraform apply
```
Again, myprofile IAM user needs to have access to decryption within a given key.
[AWS has that documented as well](https://docs.aws.amazon.com/kms/latest/developerguide/iam-policies.html#iam-policy-example-encrypt-decrypt-specific-cmks)

# Secrets manager.
AWS also has a service [AWS Secrets Manager](https://aws.amazon.com/secrets-manager/).
It is richer in features than KMS and terraform also [covers it](https://www.terraform.io/docs/providers/aws/r/secretsmanager_secret.html).
You can specify password rotation policies and group passwords together.
The reason why I don't like this approach is that changes in your secrets are not visibile in git.
This makes harder to track what changed and who made the change.
The solution also feels too complex for my day-to-day needs.

# Terraform state
While your secrets are no longer in the terraform codebase, they are present in the plaintext form in the state file.
If the state is stored in the git as well, entire approach with KMS is next to useless.
State file contains full information on the `aws_kms_secrets` data provider.
```json
"data.aws_kms_secrets.secrets": {
    "type": "aws_kms_secrets",
    "depends_on": [],
    "primary": {
        "id": "{date}",
        "attributes": {
            "id": "{date}",
            "plaintext.%": "1",
            "plaintext.master_password": "PLAINTEXT_SECRET",
            "secret.#": "1",
            "secret.3421790129.context.%": "0",
            "secret.3421790129.grant_tokens.#": "0",
            "secret.3421790129.name": "master_password",
            "secret.3421790129.payload": "AQICAHjxiIlAeQ/[...]"
        },
        "meta": {},
        "tainted": false
    },
    "deposed": [],
    "provider": "provider.aws"
},
```
Luckily, you can store the state file outside the git repo [on s3 bucket](https://www.terraform.io/docs/backends/types/s3.html).
I will write a separate post on storing the state with safe locking mechanisms.
