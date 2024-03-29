{
  description = "Kubeflow deployment using Rancher";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
        rancherClusterConfig = pkgs.writeText "rancher-cluster.yml" ''
          nodes:
            - address: 127.0.0.1
              user: root
              role:
                - controlplane
                - etcd
                - worker
          private_registries:
            - url: 127.0.0.1:5000
              is_default: true
	  services:
	    etcd:
	      snapshot: true
	      creation: 6h
	      retention: 24h
        '';
        deployKFRequirements = pkgs.writeText "deploykf-requirements.yaml" ''
          apiVersion: v1
          kind: ConfigMap
          metadata:
            name: deploykf-requirements
            namespace: kube-system
          data:
            clusterDomain: "cluster.local"
            nodeResources: |
              requests:
                cpu: 4
                memory: 16Gi
            cpuArchitecture: "x86_64"
            serviceType: "LoadBalancer"
            defaultStorageClass: |
              apiVersion: storage.k8s.io/v1
              kind: StorageClass
              metadata:
                name: standard
              provisioner: kubernetes.io/aws-ebs
              parameters:
                type: gp2
              reclaimPolicy: Retain
              allowVolumeExpansion: true
              mountOptions:
                - debug
        '';
      in {
        nixosConfigurations = {
          kubeflow-rancher = nixpkgs.lib.nixosSystem {
            system = system;
            modules = [
              ({pkgs, ...}: {
                environment.systemPackages = with pkgs; [
		  docker
                  kubernetes-helm
                  kubectl
                  rke
                ];

                virtualisation.docker = {
		  enable = true;
		  storageDriver = "overlay2";
		};

		systemd.services.docker.wantedBy = ["multi-user.target"];

                services.openssh = {
		  enable = true;
                  permitRootLogin = "yes";
		};

                users.users.root.password = "";

                networking.firewall = {
		  allowedTCPPorts = [6443 2379 2380 10250 10251 10252];
                  allowedUDPPorts = [6443 2379 2380 10250 10251 10252];
		};
              })
            ];
          };
        };
        packages = {
          default = pkgs.stdenv.mkDerivation {
            name = "kubeflow-rancher";
            src = self;

            buildInputs = with pkgs; [
	      docker
              kubernetes-helm
              kubectl
              rke
            ];

            buildPhase = ''
	      is_docker_ready() {
		docker info >/dev/null 2>&1
	      }

	      echo "Waiting for Docker daemon to be ready..."
	      retries=0
	      until is_docker_ready || [ $retries -eq 60 ]; do
		echo "Docker daemon not ready yet. Retry #$retries in 5 seconds..."
		sleep 5
		retries=$((retries + 1))
	      done

	      if ! is_docker_ready; then
		echo "Docker daemon failed to start after 5 minutes. Aborting."
		exit 1
	      fi

	      docker run -d -p 5000:5000 --restart=always --name registry registry:2

	      docker pull rancher/rancher:latest
	      docker tag rancher/rancher:latest localhost:5000/rancher/rancher:latest
	      docker push localhost:5000/rancher/rancher:latest

              rke up --config ${rancherClusterConfig}

              # Ensure the cluster meets the deployKF requirements
              kubectl apply -f ${deployKFRequirements}

              # Add the Kubeflow Helm repository
              helm repo add kubeflow https://charts.kubeflow.org
              helm repo update
            '';

            installPhase = ''
              # Install Kubeflow using Helm
                       helm install kubeflow kubeflow/kubeflow \
                         --namespace kubeflow \
                         --create-namespace \
                         --version 1.5.0 \
                         --set istio.enabled=true

                       # Create a wrapper script for easy deployment
                       mkdir -p $out/bin
                       echo '#!/bin/sh' > $out/bin/deploy-kubeflow-rancher.sh
                       echo 'rke up --config ${rancherClusterConfig}' >> $out/bin/deploy-kubeflow-rancher.sh
                       echo 'kubectl apply -f ${deployKFRequirements}' >> $out/bin/deploy-kubeflow-rancher.sh
                       echo 'helm install kubeflow kubeflow/kubeflow --namespace kubeflow --create-namespace --version 1.5.0 --set istio.enabled=true' >> $out/bin/deploy-kubeflow-rancher.sh
                       chmod +x $out/bin/deploy-kubeflow-rancher.sh
            '';
          };
        };

        apps = {
          default = {
            type = "app";
            program = "${self.packages.${system}.default}/bin/deploy-kubeflow-rancher.sh";
          };
        };
      }
    );
}
