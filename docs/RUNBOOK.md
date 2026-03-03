> # Operational Runbook — marciobolsoni.cloud
> 
> This runbook provides standard operating procedures (SOPs) for managing the **marciobolsoni.cloud** application and infrastructure. 
> 
> ## 1. Manual Deployments
> 
> While the primary workflow is automated via Git, manual deployments can be triggered directly from GitHub Actions for rollbacks or emergency hotfixes.
> 
> ### Triggering a Manual Deployment
> 
> 1.  Navigate to the **Actions** tab in the GitHub repository.
> 2.  Select the **CD — Deploy to Production** workflow from the left sidebar.
> 3.  Click the **Run workflow** dropdown on the right.
> 4.  Fill in the required inputs:
>     *   **Image Tag**: Specify the exact Docker image tag to deploy (e.g., `sha-a1b2c3d`).
>     *   **Deployment Type**: Choose `canary`.
> 5.  Click **Run workflow**.
> 
> ## 2. Rollback Procedures
> 
> The system has both automated and manual rollback capabilities.
> 
> ### Automated Rollback
> 
> **Trigger**: An automated rollback is triggered if any of the critical CloudWatch alarms enter an `ALARM` state during a canary deployment.
> 
> **Action**: No manual intervention is required. CodeDeploy will automatically stop the deployment, shift 100% of traffic back to the last known good version, and the `rollback` job in the GitHub Actions workflow will create a GitHub Issue and send a Slack notification.
> 
> ### Manual Rollback
> 
> A manual rollback can be initiated if a bug is discovered post-deployment that was not caught by the automated alarms.
> 
> #### Procedure
> 
> 1.  Navigate to the **Actions** tab in the GitHub repository.
> 2.  Select the **Manual Rollback** workflow.
> 3.  Click the **Run workflow** dropdown.
> 4.  Choose the rollback parameters:
> 
> | Parameter | Description | Example |
> | :--- | :--- | :--- |
> | **Environment** | The target environment to roll back. | `production` |
> | **Rollback Type** | The method for rollback. `previous-deployment` is the safest and most common option. | `previous-deployment` |
> | **Target Value** | Only required if rolling back to a specific image or task definition. Leave blank for `previous-deployment`. | `sha-a1b2c3d` |
> | **Reason** | A mandatory, concise reason for the rollback for the audit trail. | "Post-deployment discovery of critical UI bug on checkout page." |
> 
> 5.  Click **Run workflow**. The script will handle stopping the current deployment and forcing a new deployment of the stable version.
> 
> ## 3. Incident Response
> 
> When a production incident occurs (e.g., an automated rollback is triggered), the following steps should be taken.
> 
> ### Initial Triage
> 
> 1.  **Acknowledge the Incident**: A GitHub Issue is automatically created by the rollback workflow. The on-call engineer should assign it to themselves and acknowledge it in the relevant Slack channel.
> 2.  **Assess Impact**: Check the CloudWatch Dashboard for the production environment to understand which metrics breached their thresholds. Review application logs in CloudWatch Logs Insights for any obvious errors.
> 3.  **Confirm Rollback**: Verify in the AWS CodeDeploy console that the rollback was successful and the service is stable.
> 
> ### Root Cause Analysis (RCA)
> 
> 1.  **Analyze Logs**: Use CloudWatch Logs Insights to query logs around the time of the failed deployment. Look for error messages, stack traces, or unusual patterns.
>     ```sql
>     fields @timestamp, @message
>     | filter @logStream like /ecs-prod/
>     | filter @message like /ERROR/
>     | sort @timestamp desc
>     | limit 100
>     ```
> 2.  **Review Changes**: Examine the git commits that were part of the failed deployment to identify the code changes that likely caused the issue.
> 3.  **Document Findings**: Update the auto-generated GitHub Issue with all findings, analysis, and a hypothesis for the root cause.
> 
> ### Resolution
> 
> 1.  **Create a Hotfix**: Create a new branch from `main` to fix the issue.
> 2.  **Test Thoroughly**: Replicate the production failure in a local or staging environment and verify that the fix resolves it.
> 3.  **Deploy the Fix**: Follow the standard deployment process. The CI/CD pipeline will run all tests and checks before deploying the fix.
> 
> ## 4. Common Operational Tasks
> 
> ### Viewing Application Logs
> 
> 1.  Navigate to the **CloudWatch** service in the AWS Console.
> 2.  Go to **Log groups**.
> 3.  Find the log group for your environment, e.g., `/ecs/marciobolsoni-cloud-prod/app`.
> 4.  Click on a log stream to view logs or use **Logs Insights** for powerful querying.
> 
> ### Checking Deployment Status
> 
> 1.  Navigate to the **CodeDeploy** service in the AWS Console.
> 2.  Go to **Deployments**.
> 3.  Select the deployment group for your environment (e.g., `marciobolsoni-prod`).
> 4.  Here you can see the status of all current and past deployments, including traffic percentages and lifecycle event logs.
