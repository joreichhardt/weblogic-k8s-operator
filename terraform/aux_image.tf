# ── WebLogic Base Image (einmalig interaktiv pullen mit: make ocr-login) ────────

resource "terraform_data" "weblogic_base_image" {
  triggers_replace = {
    cluster_uid = data.external.cluster_uid.result.uid
  }

  provisioner "local-exec" {
    command = <<-EOT
      eval $(minikube docker-env --profile=${var.kube_context})
      if docker images -q ${var.weblogic_image} | grep -q .; then
        echo "WebLogic base image already present, skipping pull."
      else
        echo "Pulling WebLogic base image (requires prior: make ocr-login)..."
        docker pull ${var.weblogic_image}
      fi
    EOT
  }

  depends_on = [terraform_data.minikube_start]
}

# ── Auxiliary Image ────────────────────────────────────────────────────────────

resource "terraform_data" "aux_image" {
  triggers_replace = {
    cluster_uid = data.external.cluster_uid.result.uid
  }

  provisioner "local-exec" {
    command = <<-EOT
      eval $(minikube docker-env --profile=${var.kube_context})
      docker images -q ${var.aux_image_tag} | grep -q . && exit 0
      QUICKSTART="${abspath(path.module)}/../quickstart"
      (cd "$QUICKSTART/models/archive" && zip -r ../archive.zip wlsdeploy/)
      cd "$QUICKSTART"
      JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java)))) \
        ./tools/imagetool/bin/imagetool.sh createAuxImage \
        --tag ${var.aux_image_tag} \
        --wdtModel models/model.yaml \
        --wdtVariables models/model.properties \
        --wdtArchive models/archive.zip
    EOT
  }

  depends_on = [terraform_data.weblogic_base_image]
}
