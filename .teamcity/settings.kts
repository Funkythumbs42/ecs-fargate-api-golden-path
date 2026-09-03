/*
 * API factory. Import this repo into TeamCity once.
 *
 * From inception: Run **new-api**, fill in name / port / preset.
 * That job scaffolds Terraform + Dockerfile + Go, registers the service
 * in services.list (so this DSL grows a subproject), builds the first
 * image, and commits. After settings reload, that app has create / ship /
 * promote / rollback. Shared VPC/cluster are not created per app.
 *
 * Day-2 one-clicks live on the service subproject:
 *   create (dev)  first AWS deploy (build + infra apply, bootstrap digest)
 *   ship (dev)    build + code deploy
 *   promote       same digest, next env
 *   code / rollback  current Terraform + previous digest
 */

import java.io.File
import jetbrains.buildServer.configs.kotlin.*
import jetbrains.buildServer.configs.kotlin.buildFeatures.approval
import jetbrains.buildServer.configs.kotlin.buildSteps.script
import jetbrains.buildServer.configs.kotlin.triggers.finishBuildTrigger
import jetbrains.buildServer.configs.kotlin.triggers.vcs

version = "2024.12"

val awsRegion = "eu-west-1"
val ecrRegistry = "123456789012.dkr.ecr.eu-west-1.amazonaws.com"

fun safeId(name: String) = name.replace("-", "_")

fun loadServices(): List<String> {
    val f = File(DslContext.baseDir, "services.list")
    if (!f.exists()) return listOf("example-api")
    return f.readLines().map { it.trim() }.filter { it.isNotEmpty() && !it.startsWith("#") }
}

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
    description = "Golden-path factory. Click new-api to create an application from nothing. Each services/* line becomes a subproject with its own pipelines."

    params {
        param("aws.region", awsRegion)
        param("aws.connection.id", "aws-oidc-example")
        param("ecr.registry", ecrRegistry)
    }

    buildType(NewApi)
    buildType(LocalChecks)

    loadServices().forEach { svc ->
        subProject(serviceProject(svc))
    }
}

object LocalChecks : BuildType({
    id("LocalChecks")
    name = "local-checks"
    description = "Offline-ish: docker build of example-api + terraform fmt/validate."
    checkout()
    steps {
        script {
            name = "local-checks"
            scriptContent = """
                set -euo pipefail
                ROOT="${'$'}{REPO_HOST_PATH:-%teamcity.build.checkoutDir%}"
                export REPO_HOST_PATH="${'$'}ROOT"
                bash "${'$'}ROOT/scripts/local-checks.sh"
            """.trimIndent()
        }
    }
})

object NewApi : BuildType({
    id("NewApi")
    name = "new-api"
    description = "FROM INCEPTION. Prompted name/port/preset. Scaffolds Terraform, Docker, Go, TeamCity pipelines; builds the first image. One click."

    checkout()

    params {
        text(
            "new.name",
            "",
            display = ParameterDisplay.PROMPT,
            allowEmpty = false,
            label = "Service name (e.g. orders-api)"
        )
        text(
            "new.port",
            "8080",
            display = ParameterDisplay.PROMPT,
            allowEmpty = false,
            label = "Container port"
        )
        text(
            "new.preset",
            "small",
            display = ParameterDisplay.PROMPT,
            allowEmpty = false,
            label = "CPU/mem preset: small | medium | large"
        )
        text(
            "new.host",
            "",
            display = ParameterDisplay.PROMPT,
            allowEmpty = true,
            label = "Optional dev host header (default: <name>.dev.example.invalid)"
        )
        param("env.INCEPTION_GIT", "1")
    }

    steps {
        script {
            name = "inception: scaffold, pipelines, first image"
            scriptContent = """
                set -euo pipefail
                ROOT="%teamcity.build.checkoutDir%"
                cd "${'$'}ROOT"
                export INCEPTION_GIT=1
                bash scripts/inception.sh "%new.name%" "%new.port%" "%new.preset%" "%new.host%"
                echo "##teamcity[buildStatus text='created %new.name% image=%new.name%:inception']"
            """.trimIndent()
        }
    }
})

fun serviceProject(svc: String): Project {
    val sid = safeId(svc)
    return Project {
        id("Svc_$sid")
        name = svc
        description = "Pipelines for $svc. create = first deploy, ship = day-2 code, promote = same digest, rollback = current infra + old digest."

        params {
            param("service.name", svc)
            param("ecr.repository", svc)
            param("aws.region", awsRegion)
        }

        val buildImage = BuildType {
            id("Svc_${sid}_Build")
            name = "build"
            description = "docker build, push to ECR, publish image_digest.txt. No Terraform."
            artifactRules = "image_digest.txt"
            checkout()
            params {
                param("service.name", svc)
                param("aws.region", awsRegion)
                param("aws.role.arn", "arn:aws:iam::123456789012:role/teamcity-${svc}-ci")
                param("ecr.registry", ecrRegistry)
                param("ecr.repository", svc)
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
                          -t "${'$'}IMAGE" "services/%service.name%"
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
                param("service.name", svc)
                param("deploy.env", env)
                param("aws.region", awsRegion)
                param("aws.role.arn", "arn:aws:iam::123456789012:role/teamcity-${svc}-${env}")
                param("env.SERVICE_NAME", svc)
                param("env.DEPLOY_ENV", env)
            }
        }

        fun digestFromBuild(bt: BuildType) {
            bt.dependencies {
                snapshot(buildImage, snapshotOk())
                artifacts(buildImage) {
                    artifactRules = "image_digest.txt"
                    cleanDestination = true
                }
            }
        }

        val infraApplyDev = BuildType {
            id("Svc_${sid}_InfraApplyDev")
            name = "infra apply (dev)"
            description = "Platform + service Terraform. Preserves running digest; first create uses build digest."
            checkout()
            awsOn(this, "dev")
            steps { runScript("infra apply", "scripts/infra-apply.sh") }
            digestFromBuild(this)
            triggers {
                vcs {
                    branchFilter = "+:main"
                    triggerRules = """
                        +:root=*:modules/**
                        +:root=*:platform/**
                        +:root=*:services/$svc/envs/**
                    """.trimIndent()
                }
            }
        }

        val infraApplyStaging = BuildType {
            id("Svc_${sid}_InfraApplyStaging")
            name = "infra apply (staging)"
            checkout()
            awsOn(this, "staging")
            steps { runScript("infra apply", "scripts/infra-apply.sh") }
            digestFromBuild(this)
        }

        val infraApplyProd = BuildType {
            id("Svc_${sid}_InfraApplyProd")
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
            id("Svc_${sid}_InfraPlanDev")
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
                        +:root=*:modules/**
                        +:root=*:platform/**
                        +:root=*:services/$svc/envs/**
                    """.trimIndent()
                }
            }
        }

        val codePlanDev = BuildType {
            id("Svc_${sid}_CodePlanDev")
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
                        +:root=*:services/$svc/**
                        -:root=*:services/$svc/envs/**
                    """.trimIndent()
                }
            }
        }

        val codeDeployDev = BuildType {
            id("Svc_${sid}_CodeDeployDev")
            name = "code deploy (dev)"
            checkout()
            awsOn(this, "dev")
            steps { runScript("code apply", "scripts/code-apply.sh") }
            digestFromBuild(this)
        }

        val codeDeployStaging = BuildType {
            id("Svc_${sid}_CodeDeployStaging")
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
            id("Svc_${sid}_CodeDeployProd")
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
                id("Svc_${sid}_Rollback_$envId")
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
            id("Svc_${sid}_CreateDev")
            name = "create (dev)"
            description = "First AWS deploy: build + infra apply with that digest."
            type = BuildTypeSettings.Type.COMPOSITE
            dependencies {
                snapshot(buildImage, snapshotOk())
                snapshot(infraApplyDev, snapshotOk())
            }
        }

        val shipDev = BuildType {
            id("Svc_${sid}_ShipDev")
            name = "ship (dev)"
            description = "Day-2 one click: build + code deploy. No infra apply."
            type = BuildTypeSettings.Type.COMPOSITE
            triggers {
                vcs {
                    branchFilter = "+:main"
                    triggerRules = """
                        +:root=*:services/$svc/**
                        -:root=*:services/$svc/envs/**
                    """.trimIndent()
                }
            }
            dependencies {
                snapshot(buildImage, snapshotOk())
                snapshot(codeDeployDev, snapshotOk())
            }
        }

        val promoteStaging = BuildType {
            id("Svc_${sid}_PromoteStaging")
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
            id("Svc_${sid}_PromoteProd")
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
}
