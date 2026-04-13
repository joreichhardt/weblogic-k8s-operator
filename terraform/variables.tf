variable "kube_context" {
  description = "kubectl context to use (e.g. minikube)"
  type        = string
  default     = "minikube"
}

variable "operator_namespace" {
  description = "Namespace for the WebLogic Kubernetes Operator"
  type        = string
  default     = "weblogic-operator-ns"
}

variable "domain_namespace" {
  description = "Namespace for the WebLogic Domain"
  type        = string
  default     = "weblogic-domain1-ns"
}

variable "weblogic_operator_version" {
  description = "WebLogic Kubernetes Operator Helm chart version"
  type        = string
  default     = "4.3.7"
}

variable "ocr_username" {
  description = "Oracle Container Registry username (Oracle SSO email)"
  type        = string
  sensitive   = true
}

variable "ocr_password" {
  description = "Oracle Container Registry password (Oracle SSO password)"
  type        = string
  sensitive   = true
}
