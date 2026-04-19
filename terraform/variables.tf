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

variable "aux_image_tag" {
  description = "Tag des Auxiliary Image (quick-start-aux-image:vN)"
  type        = string
  default     = "quick-start-aux-image:v7"
}

variable "weblogic_image" {
  description = "WebLogic base image aus Oracle Container Registry"
  type        = string
  default     = "container-registry.oracle.com/middleware/weblogic:15.1.1.0-generic-jdk17-ol8"
}
