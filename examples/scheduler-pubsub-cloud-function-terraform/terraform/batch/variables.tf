variable "project_id" {
  description = "Project ID to create Cloud Function"
  type        = string
}

variable "location" {
  description = "The location of all resources"
  type        = string
}

variable "schedule" {
  description = "Schedules are specified using unix-cron format. E.g. every minute: * * * * *"
  type        = string
}

variable "message" {
  description = "The message to be published"
  type        = string
}

variable "source_dir" {
  description = "The source directory containing the function source code"
  type        = string
}

variable "function_name" {
  description = "The name of the function"
  type        = string
}

variable "runtime" {
  description = "The runtime in which to run the function"
  type        = string
}

variable "entrypoint" {
  description = "The name of the function (as defined in source code)"
  type        = string
}

variable "build_env_variables" {
  description = "A set of key/value environment variable pairs to be used when building the function"
  type        = map(string)
  default     = null
}

variable "runtime_env_variables" {
  description = "A set of key/value environment variable pairs to assign to the function"
  type        = map(string)
  default     = null
}

variable "runtime_secret_env_variables" {
  description = "A set of key/value environment variable pairs to assign to the function from secret manager"
  type = set(object({
    key     = string
    secret  = string
    version = string
  }))
  default = null
}
