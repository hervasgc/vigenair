import {
  GcpDeploymentHandler,
  UiDeploymentHandler,
  UserConfigManager,
} from "./common.js";

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

(async () => {
  console.log("Iniciando deploy automatizado pelo Agente...");

  const response = {
    gcpProjectId: requireEnv("VIGENAIR_GCP_PROJECT_ID"),
    deployGcpComponents: true,
    deployUi: true,
    gcpRegion: requireEnv("VIGENAIR_GCP_REGION"),
    gcsLocation: requireEnv("VIGENAIR_GCS_LOCATION"),
    webappDomainAccess: false,
    vertexAiRegion: requireEnv("VIGENAIR_VERTEXAI_REGION"),
  };

  // 1. Aplica as configurações substituindo os placeholders nos arquivos (ex: <gcp-project-id>)
  UserConfigManager.setUserConfig(response);

  // 2. Deploy do Backend (Cloud Function, Buckets, Eventarc, Permissões IAM)
  await GcpDeploymentHandler.checkGcloudAuth();
  GcpDeploymentHandler.deployGcpComponents();

  // 3. Deploy do Frontend (Projeto Apps Script e Web App Angular)
  await UiDeploymentHandler.createScriptProject();
  UiDeploymentHandler.deployUi();
  
  console.log("Deploy finalizado com sucesso pelo Agente!");
})();
