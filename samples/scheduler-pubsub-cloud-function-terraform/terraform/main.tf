module "batch_helloworld" {
  source = "./batch"

  project_id = "your-project-id"
  location   = "asia-northeast1"

  schedule = "0 0 * * *"
  message  = base64encode("{\"name\": \"Haru\"}")

  source_dir          = "../helloworld"
  function_name       = "hello-pubsub"
  runtime             = "go121"
  entrypoint          = "HelloPubSub"
  build_env_variables = null
  runtime_env_variables = {
    SERVICE_CONFIG_TEST = "config_value"
  }
  runtime_secret_env_variables = [
    {
      key     = "SECRET_CONFIG_TEST"
      secret  = "SECRET_NAME"
      version = "1"
    },
  ]
}
