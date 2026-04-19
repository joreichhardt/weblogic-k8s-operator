# ── Auxiliary Image ───────────────────────────────────────────────────────────
#
# Baut das Aux-Image nur wenn es in Minikubes Docker-Daemon noch nicht existiert.

resource "terraform_data" "aux_image" {
  triggers_replace = {
    cluster_uid = data.external.cluster_uid.result.uid
  }

  provisioner "local-exec" {
    command = <<-EOT
      eval $(minikube docker-env --profile=${var.kube_context})
      docker images -q ${var.aux_image_tag} | grep -q . && exit 0
      cd ${path.module}/../quickstart/models/archive && zip -r ../archive.zip wlsdeploy/
      cd ${path.module}/../quickstart
      JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java)))) \
        ./tools/imagetool/bin/imagetool.sh createAuxImage \
        --tag ${var.aux_image_tag} \
        --wdtModel models/model.yaml \
        --wdtVariables models/model.properties \
        --wdtArchive models/archive.zip
    EOT
  }

  depends_on = [terraform_data.minikube_start]
}
