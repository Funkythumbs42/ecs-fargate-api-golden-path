/*
 * API factory. Import this repo into TeamCity once.
 *
 * From inception: Run **new-api**, fill in name / port / preset / ALB / git.
 * That job renders templates/service-api into a new (or empty existing)
 * GitHub repo, registers a TeamCity project whose VCS root is THAT repo,
 * and records the ECR name here. After the app project loads .teamcity,
 * run **create (dev)** on the APP project (not here).
 *
 * This factory does not generate a subproject per services.list line.
 * Day-2 ship / promote / rollback live on the app project.
 */

import jetbrains.buildServer.configs.kotlin.*
import jetbrains.buildServer.configs.kotlin.buildFeatures.approval
import jetbrains.buildServer.configs.kotlin.buildSteps.script

version = "2024.12"

val awsRegion = "eu-west-1"
val ecrRegistry = "784318225077.dkr.ecr.eu-west-1.amazonaws.com"

fun BuildType.checkout() {
    vcs {
        root(DslContext.settingsRoot)
        cleanCheckout = true
    }
}

class LocalChecks : BuildType({
    id("LocalChecks")
    name = "local-checks"
    description = "Offline-ish: docker build of templates/service-api + terraform fmt/validate of modules and platform."
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

class NewApi : BuildType({
    id("NewApi")
    name = "new-api"
    description = "FROM INCEPTION. Prompted name/port/preset/ALB/git. Creates a private GitHub app repo, registers its TeamCity project, builds the first image. One click."

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
            label = "Optional DNS / CNAME hint for the dedicated ALB (not a Host-header rule)"
        )
        select(
            "new.alb.internal",
            "false",
            display = ParameterDisplay.PROMPT,
            label = "ALB scheme",
            description = "Each app gets its own ALB. Internet-facing (default) lands in public subnets; internal lands in private subnets. Tasks stay private either way.",
            options = listOf(
                "false" to "Internet-facing (public subnets)",
                "true" to "Internal (private subnets)"
            )
        )
        select(
            "new.git.mode",
            "create",
            display = ParameterDisplay.PROMPT,
            label = "Git location",
            description = "create = new private GitHub repo (default). existing = attach an existing GitHub repo (push if empty, pointer-only if not).",
            options = listOf(
                "create" to "Create a new private GitHub repo",
                "existing" to "Use an existing GitHub repo"
            )
        )
        text(
            "new.git.repo",
            "",
            display = ParameterDisplay.PROMPT,
            allowEmpty = true,
            label = "GitHub repo (owner/name or URL). Required for existing. Optional for create (defaults to <you>/<service-name>)."
        )
        param("env.INCEPTION_GIT", "1")
    }

    steps {
        script {
            name = "inception: app repo, TeamCity project, first image"
            scriptContent = """
                set -euo pipefail
                ROOT="%teamcity.build.checkoutDir%"
                cd "${'$'}ROOT"
                export INCEPTION_GIT=1
                export GIT_MODE="%new.git.mode%"
                export GIT_REPO="%new.git.repo%"
                export ALB_INTERNAL="%new.alb.internal%"
                export TEAMCITY_URL="%teamcity.serverUrl%"
                bash scripts/inception.sh "%new.name%" "%new.port%" "%new.preset%" "%new.host%" "%new.git.mode%" "%new.git.repo%" "%new.alb.internal%"
                echo "##teamcity[buildStatus text='created %new.name% image=%new.name%:inception']"
            """.trimIndent()
        }
    }
})

fun platformAws(bt: BuildType, env: String) {
    bt.params {
        param("deploy.env", env)
        param("aws.region", awsRegion)
        param("aws.role.arn", "arn:aws:iam::784318225077:role/teamcity-platform-${env}")
        param("env.DEPLOY_ENV", env)
    }
}

class PlatformPlanDev : BuildType({
    id("PlatformPlanDev")
    name = "platform plan (dev)"
    description = "Plan shared VPC/NAT/cluster/ECR. Does not plan app ALBs."
    checkout()
    platformAws(this, "dev")
    steps {
        script {
            name = "platform plan"
            scriptContent = """
                set -euo pipefail
                export AWS_DEFAULT_REGION="%aws.region%"
                export DEPLOY_ENV="%deploy.env%"
                bash scripts/platform-plan.sh
            """.trimIndent()
        }
    }
})

class PlatformApplyDev : BuildType({
    id("PlatformApplyDev")
    name = "platform apply (dev)"
    description = "Apply shared VPC/NAT/cluster/ECR. App ALBs are not here. Needed once after new-api adds an ECR name."
    checkout()
    platformAws(this, "dev")
    steps {
        script {
            name = "platform apply"
            scriptContent = """
                set -euo pipefail
                export AWS_DEFAULT_REGION="%aws.region%"
                export DEPLOY_ENV="%deploy.env%"
                bash scripts/platform-apply.sh
            """.trimIndent()
        }
    }
})

class PlatformApplyStaging : BuildType({
    id("PlatformApplyStaging")
    name = "platform apply (staging)"
    checkout()
    platformAws(this, "staging")
    steps {
        script {
            name = "platform apply"
            scriptContent = """
                set -euo pipefail
                export AWS_DEFAULT_REGION="%aws.region%"
                export DEPLOY_ENV="%deploy.env%"
                bash scripts/platform-apply.sh
            """.trimIndent()
        }
    }
})

class PlatformApplyProd : BuildType({
    id("PlatformApplyProd")
    name = "platform apply (prod)"
    checkout()
    platformAws(this, "prod")
    steps {
        script {
            name = "platform apply"
            scriptContent = """
                set -euo pipefail
                export AWS_DEFAULT_REGION="%aws.region%"
                export DEPLOY_ENV="%deploy.env%"
                bash scripts/platform-apply.sh
            """.trimIndent()
        }
    }
    features {
        approval {
            approvalRules = "group:prod-approvers"
            timeout = 1440
        }
    }
})

project {
    description = "Golden-path factory. Click new-api to create a standalone app repo (Go + Terraform + TeamCity). Platform apply is shared VPC/cluster/ECR only — each app owns its ALB."

    params {
        param("aws.region", awsRegion)
        param("aws.connection.id", "aws-oidc-example")
        param("ecr.registry", ecrRegistry)
    }

    buildType(NewApi())
    buildType(LocalChecks())
    buildType(PlatformPlanDev())
    buildType(PlatformApplyDev())
    buildType(PlatformApplyStaging())
    buildType(PlatformApplyProd())
}
