---
date: "2019-06-24T00:00:00Z"
summary: How to organise terrafrom project structure with terragrunt.
title: Terraform production ready project structure
---

[Terraform](https://www.terraform.io/intro/index.html) is becoming a standard in managing a infrastructure as code.
List of [providers](https://www.terraform.io/docs/providers/index.html) is growing like never before.
It is fairly easy to drink too much cool-aid.
While it is a very powerful tool, it has limitations.
Some of them can be solved easily, some require obscure hacks.
Terraform is relatively young and it misses some critical tooling, that you need to create on your own.
In this post I will show how to *structure* a terraform code base to manage multiple environments.
Most of the solutions revolve around [terragrunt](https://github.com/gruntwork-io/terragrunt).
It is a thin wrapper for Terraform that provides extra tools for working with multiple Terraform modules.


## Terraform up and running
If you have not read [terraform up and running](https://www.terraformupandrunning.com/) book, do it.
Even if you think you know how to use terraform.
The most important chapter are:
* How to manage terraform state
* Creating reusable modules
* How to use terraform as a team

I will cover some of these issues in this post as well.

## Modules and pins
Any sane company has more than one environment.
Usually it looks like: `production, staging, dev`.
Environments come and go, change over time.
If you manage them, one of your goals is to keep in them aligned.
Have some key parameters such as instance types, volume sizes different.
The architecture should stay the same.
Updating set of clusters should be as easy as updating a single one.

To avoid code duplication use [terraform modules](https://www.terraform.io/docs/configuration/modules.html).

This way you can reuse the code you write across multiple environments.
Terraform documentation is pretty good at explaining what they are, so I won't be writing much about it here.
What you should be aware of is that modules can be *Pinned* to a specific version.
Meaning, when you provide source, it can be git repository url with a `ref` tag specified.
```terraform
module "vpc" {
  source = "git::https://example.com/vpc.git?ref=v1.2.0"
}
```
This way you can gradually upgrade your clusters by upgrading from dev to staging and later to prod.
Real question is:

> I am supposed to manage my entire cluster with a single module or use multiple ones?

Having a global module per cluster might not be a terrible idea if your infrastructure is fairly simple.
If you grow in complexity, you want to separate modules and their instantiation.

1. If something goes wrong, it goes wrong in the entire cluster.
2. You can do only one change on the cluster in parallel. If you use [state locking](https://www.terraform.io/docs/state/locking.html) it will result in an error. If not, risk of damaging the cluster state is quite big.
2. You risk creating modules that are hard to reason about. This is the same antipattern as creating a single class to manage entire project.

## Project structure with fine grained modules
If you are using cloud provider such as AWS or Google Cloud, you know that resources are created "per" anything.
For example:
* IAM users or s3 buckets are global at the account level
* ECR repos are created per region
* RDS, ECS clusters are per VPC/cluster

So we need to be able to create resources per cluster/environment, but also some globally shared resources among clusters.
With terragrunt you can [can create a tree structure](https://github.com/gruntwork-io/terragrunt#motivation) that will describe your needs.
In my case, nested level are:
* aws account
* aws region
* cluster name

Each one of these levels can have their own `_global` directory, that will hold global state per `account/region/cluster`.
The directory structure for my terraform code looks like this:

```
$ tree -d -L 3
├── dev
│   ├── _global
│   ├── ap-southeast-2
│   │   ├── _global
│   │   ├── mgmt
│   │   └── dev
│   └── eu-west-1
│       ├── _global
│       ├── mgmt
│       ├── staging
│       ├── dev1
│       └── dev2
└── prod
    ├── _global
    ├── ap-southeast-2
    │   ├── _global
    │   ├── prod
    │   └── mgmt
    └── us-east-1
        ├── _global
        ├── prod
        └── mgmt
```
Each directory here creates a workspace where given terraform modules can be instantiated.
Hierarchy allows customization on any level with variables propagating to lower levels to avoid duplication.

As mentioned, some modules get provisioned per cluster. Grouping is per `data-stores, networking, services` etc.
Structure for a specific _dev1_ cluster.
```
$ tree -d -L 3
dev1
├── data-stores
│   ├── rds-db
│   ├── rds-other-db
│   └── s3-buckets
├── kms-key
├── logging
├── networking
│   ├── albs
│   └── route53
├── services
│   ├── service1
│   ├── service2
│   ├── service3
│   ├── service4
│   └── ecs-cluster
└── vpc
```

## Terragrunt module instantiation
Each directory we listed so far contain single `*.tfvars` file.
```
$ ls dev/eu-west-1/dev1/services/service1/
terraform.tfvars
```
This file provisions a given terraform module
```
terragrunt = {
  terraform {
    source = "git::git@github.com:github-account/repo-name.git//services/service1?ref=given-tag"
  }
  include = {
    path = "${find_in_parent_folders()}"
  }
  dependencies = {
    paths = ["../ecs-cluster"]
  }
}

cpu                       = 128
memory                    = 200
desired_number_of_tasks   = 2
alb_listener_custom_rules = [
  {
    port     = 443,
    path     = "/*",
    host     = "foo.com",
    priority = 250,
  },
  {
    port     = 80,
    path     = "/*",
    host     = "foo.com",
    priority = 251,
  }
]

```
In the snippet above you can see `terragrunt` bracket block that describes the module to setup.
Outside brackets are variables passed into the module.
There is [a lot you can customize for terragrunt configuration](https://github.com/gruntwork-io/terragrunt#motivation-2).
You can pass env variables, arguments to terraform, add tfvar files

### Propagating variables from higher levels
There are variables that are constant at some level and you don't want to replicate them.
For example, when you use multiple aws accounts, you have to name them and keep the name consistent.
For this you can define `account.tfvars` file with contents like bellow.

```
aws_account_name = "dev"
```
This variable should be automatically passed to any terraform module that gets created in directory lower in hierarchy.
This doesn't happen automatically though.
In the snippet above each module gets created with [find_in_parent_folders](https://github.com/gruntwork-io/terragrunt#find_in_parent_folders).
This causes terragrunt to search `*tfvars` files higher in the directory structure.
Lets create a `terraform.tfvars` file at the root (account level) of the hierarchy.
```
terragrunt = {
  terraform {
    extra_arguments "common_vars" {
      commands = ["${get_terraform_commands_that_need_vars()}"]
      optional_var_files = [
        "${get_tfvars_dir()}/${find_in_parent_folders("account.tfvars", "skip-account-if-does-not-exist")}",
        "${get_tfvars_dir()}/${find_in_parent_folders("region.tfvars", "skip-region-if-does-not-exist")}",
        "${get_tfvars_dir()}/${find_in_parent_folders("env.tfvars", "skip-env-if-does-not-exist")}",
        "${get_tfvars_dir()}/terraform.tfvars"
      ]
    }
  }
}
```
This file will cause terragrunt to include `account.tfvars`, `region.tfvars`, `env.tfvars` when needed.
This way, variable `aws_account_name` doesn't have to copy-pasted each time when it is needed.

## What's next?
If you want to organize your terraform project as shown, check out [terragrunt docs on keeping the code DRY](https://github.com/gruntwork-io/terragrunt#keep-your-terraform-code-dry).
If you have any questions or need help, don't be afraid to ask in the comments :)
