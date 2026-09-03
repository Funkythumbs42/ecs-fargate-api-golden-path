/*
 * TeamCity Kotlin DSL for THIS app repo (example-api).
 *
 * Versioned settings VCS root MUST be this repository. Pipelines check
 * out the app, not the factory. Docker build context is the repo root.
 *
 * One-clicks: create (dev), ship (dev), promote, rollback.
 * This app owns its ALB; curl the alb_dns_name output, no Host header.
 */

import jetbrains.buildServer.configs.kotlin.*
import jetbrains.buildServer.configs.kotlin.buildFeatures.approval
import jetbrains.buildServer.configs.kotlin.buildSteps.script
import jetbrains.buildServer.configs.kotlin.triggers.finishBuildTrigger
import jetbrains.buildServer.configs.kotlin.triggers.vcs

version = "2024.12"

val serviceName = "example-api"
val awsRegion = "eu-west-1"
val ecrRegistry = "784318225077.dkr.ecr.eu-west-1.amazonaws.com"

fun snapshotOk(): SnapshotDependency.() -> Unit = {
    onDependencyFailure = FailureAction.FAIL_TO_START
    reuseBuilds = ReuseBuilds.SUCCESSFUL
    synchronizeRevisions = true
}

fun BuildType.checkout() {
    vcs {
        root(DslContext.settingsRoot)
        cleanCheckout = true
    }
}

fun BuildSteps.runScript(stepName: String, file: String) {
    script {
        name = stepName
        scriptContent = """
            set -euo pipefail
            export AWS_DEFAULT_REGION="%aws.region%"
            export SERVICE_NAME="%service.name%"
            export DEPLOY_ENV="%deploy.env%"
            export IMAGE_DIGEST="${'$'}{IMAGE_DIGEST:-}"
            if [ -z "${'$'}IMAGE_DIGEST" ] && [ -f image_digest.txt ]; then
              IMAGE_DIGEST=${'$'}(tr -d '[:space:]' < image_digest.txt)
              export IMAGE_DIGEST
            fi
            bash "$file"
        """.trimIndent()
    }
}

project {
    description = "Pipelines for $serviceName. create = first deploy (ALB + service), ship = day-2 code, promote = same digest, rollback = current infra + old digest."

    params {
        param("service.name", serviceName)
        param("ecr.repository", serviceName)
        param("aws.region", awsRegion)
        param("aws.connection.id", "aws-oidc-example")
        param("ecr.registry", ecrRegistry)
    }

    val buildImage = BuildType {
        id("Build")
        name = "build"
        description = "docker build from repo root, push to ECR, publish image_digest.txt. No Terraform."
        artifactRules = "image_digest.txt"
        checkout()
        params {
            param("service.name", serviceName)
            param("aws.region", awsRegion)
            param("aws.role.arn", "arn:aws:iam::784318225077:role/teamcity-${serviceName}-ci")
            param("ecr.registry", ecrRegistry)
            param("ecr.repository", serviceName)
        }
        steps {
            script {
                name = "Build, push, export digest"
                scriptContent = """
                    set -euo pipefail
                    export AWS_DEFAULT_REGION="%aws.region%"
                    aws sts get-caller-identity
                    REGISTRY="%ecr.registry%"
                    REPO="%ecr.repository%"
                    TAG="%build.number%"
                    IMAGE="${'$'}REGISTRY/${'$'}REPO:${'$'}TAG"
                    aws ecr get-login-password --region "%aws.region%" \
                      | docker login --username AWS --password-stdin "${'$'}REGISTRY"
                    docker build \
                      --build-arg VERSION="%build.vcs.number%" \
                      --build-arg SERVICE_NAME="%service.name%" \
                      -t "${'$'}IMAGE" .
                    docker push "${'$'}IMAGE"
                    DIGEST=${'$'}(aws ecr describe-images --repository-name "${'$'}REPO" \
                      --image-ids imageTag="${'$'}TAG" \
                      --query 'imageDetails[0].imageDigest' --output text)
                    echo "${'$'}DIGEST" > image_digest.txt
                    echo "##teamcity[setParameter name='env.IMAGE_DIGEST' value='${'$'}DIGEST']"
                """.trimIndent()
            }
        }
    }

    fun awsOn(bt: BuildType, env: String) {
        bt.params {
            param("service.name", serviceName)
            param("deploy.env", env)
            param("aws.region", awsRegion)
            param("aws.role.arn", "arn:aws:iam::784318225077:role/teamcity-${serviceName}-${env}")
            param("env.SERVICE_NAME", serviceName)
            param("env.DEPLOY_ENV", env)
        }
    }

    fun digestFromBuild(bt: BuildType) {
        bt.dependencies {
            snapshot(buildImage, snapshotOk())
            artifacts(buildImage) {
                artifactRules = "image_digest.txt"
                cleanDestination = false
            }
        }
    }

    val infraApplyDev = BuildType {
        id("InfraApplyDev")
        name = "infra apply (dev)"
        description = "This app's Terraform (ALB + service). Preserves running digest; first create uses build digest."
        checkout()
        awsOn(this, "dev")
        steps { runScript("infra apply", "scripts/infra-apply.sh") }
        digestFromBuild(this)
        triggers {
            vcs {
                branchFilter = "+:main"
                triggerRules = """
                    +:root=*:envs/**
                """.trimIndent()
            }
        }
    }

    val infraApplyStaging = BuildType {
        id("InfraApplyStaging")
        name = "infra apply (staging)"
        checkout()
        awsOn(this, "staging")
        steps { runScript("infra apply", "scripts/infra-apply.sh") }
        digestFromBuild(this)
    }

    val infraApplyProd = BuildType {
        id("InfraApplyProd")
        name = "infra apply (prod)"
        checkout()
        awsOn(this, "prod")
        steps { runScript("infra apply", "scripts/infra-apply.sh") }
        digestFromBuild(this)
        features {
            approval {
                approvalRules = "group:prod-approvers"
                timeout = 1440
            }
        }
    }

    val infraPlanDev = BuildType {
        id("InfraPlanDev")
        name = "infra plan (dev)"
        checkout()
        awsOn(this, "dev")
        steps { runScript("infra plan", "scripts/infra-plan.sh") }
        digestFromBuild(this)
        triggers {
            vcs {
                branchFilter = """
                    +:*
                    -:main
                """.trimIndent()
                triggerRules = """
                    +:root=*:envs/**
                """.trimIndent()
            }
        }
    }

    val codePlanDev = BuildType {
        id("CodePlanDev")
        name = "code plan (dev)"
        description = "PR gate. Fails if the plan touches anything but task def / service."
        checkout()
        awsOn(this, "dev")
        steps { runScript("code plan", "scripts/code-plan.sh") }
        digestFromBuild(this)
        triggers {
            vcs {
                branchFilter = """
                    +:*
                    -:main
                """.trimIndent()
                triggerRules = """
                    +:root=*:**
                    -:root=*:envs/**
                    -:root=*:*.md
                """.trimIndent()
            }
        }
    }

    val codeDeployDev = BuildType {
        id("CodeDeployDev")
        name = "code deploy (dev)"
        checkout()
        awsOn(this, "dev")
        steps { runScript("code apply", "scripts/code-apply.sh") }
        digestFromBuild(this)
    }

    val codeDeployStaging = BuildType {
        id("CodeDeployStaging")
        name = "code deploy (staging)"
        checkout()
        awsOn(this, "staging")
        steps { runScript("code apply", "scripts/code-apply.sh") }
        digestFromBuild(this)
        dependencies {
            snapshot(codeDeployDev, snapshotOk())
        }
    }

    val codeDeployProd = BuildType {
        id("CodeDeployProd")
        name = "code deploy (prod)"
        checkout()
        awsOn(this, "prod")
        steps { runScript("code apply", "scripts/code-apply.sh") }
        digestFromBuild(this)
        features {
            approval {
                approvalRules = "group:prod-approvers"
                timeout = 1440
            }
        }
        dependencies {
            snapshot(codeDeployStaging, snapshotOk())
        }
    }

    fun rollback(env: String, envId: String, approve: Boolean): BuildType {
        val bt = BuildType {
            id("Rollback_$envId")
            name = "rollback ($env)"
            description = "Current main Terraform + digest you type. New revision. Never family:N, never Re-run."
            checkout()
            awsOn(this, env)
            params {
                text(
                    "rollback.digest",
                    "",
                    display = ParameterDisplay.PROMPT,
                    allowEmpty = false,
                    label = "Image digest to roll back to"
                )
                param("env.IMAGE_DIGEST", "%rollback.digest%")
            }
            steps { runScript("code rollback", "scripts/code-apply.sh") }
            if (approve) {
                features {
                    approval {
                        approvalRules = "group:prod-approvers"
                        timeout = 1440
                    }
                }
            }
        }
        return bt
    }

    val createDev = BuildType {
        id("CreateDev")
        name = "create (dev)"
        description = "First AWS deploy: build + infra apply (dedicated ALB + service) with that digest."
        type = BuildTypeSettings.Type.COMPOSITE
        dependencies {
            snapshot(buildImage, snapshotOk())
            snapshot(infraApplyDev, snapshotOk())
        }
    }

    val shipDev = BuildType {
        id("ShipDev")
        name = "ship (dev)"
        description = "Day-2 one click: build + code deploy. No infra apply."
        type = BuildTypeSettings.Type.COMPOSITE
        triggers {
            vcs {
                branchFilter = "+:main"
                triggerRules = """
                    +:root=*:**
                    -:root=*:envs/**
                    -:root=*:*.md
                """.trimIndent()
            }
        }
        dependencies {
            snapshot(buildImage, snapshotOk())
            snapshot(codeDeployDev, snapshotOk())
        }
    }

    val promoteStaging = BuildType {
        id("PromoteStaging")
        name = "promote (staging)"
        type = BuildTypeSettings.Type.COMPOSITE
        triggers {
            finishBuildTrigger {
                buildType = "${shipDev.id}"
                successfulOnly = true
                branchFilter = "+:main"
            }
        }
        dependencies {
            snapshot(shipDev, snapshotOk())
            snapshot(codeDeployStaging, snapshotOk())
        }
    }

    val promoteProd = BuildType {
        id("PromoteProd")
        name = "promote (prod)"
        type = BuildTypeSettings.Type.COMPOSITE
        triggers {
            finishBuildTrigger {
                buildType = "${promoteStaging.id}"
                successfulOnly = true
                branchFilter = "+:main"
            }
        }
        dependencies {
            snapshot(promoteStaging, snapshotOk())
            snapshot(codeDeployProd, snapshotOk())
        }
    }

    buildType(buildImage)
    buildType(infraPlanDev)
    buildType(infraApplyDev)
    buildType(infraApplyStaging)
    buildType(infraApplyProd)
    buildType(codePlanDev)
    buildType(codeDeployDev)
    buildType(codeDeployStaging)
    buildType(codeDeployProd)
    buildType(rollback("dev", "Dev", false))
    buildType(rollback("staging", "Staging", false))
    buildType(rollback("prod", "Prod", true))
    buildType(createDev)
    buildType(shipDev)
    buildType(promoteStaging)
    buildType(promoteProd)
}
