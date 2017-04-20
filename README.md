# OMSDeploy_ManagedServices
Automate deployment of a standardized OMS workspace and linked Automation Account.  The template contains base settings including generic performance alerts, data collection (performance, basic events), and more.  Additionally, a runbook is included which will collect alerts from 'downstream' workspaces in a managed services scenario and bubble the alerts to the 'master' workspace.  

Template design is based on templates provided by Kristian Nese here:  https://github.com/Azure/azure-quickstart-templates/tree/master/oms-all-deploy
