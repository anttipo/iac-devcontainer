FROM ubuntu:bionic as rover_version

ARG versionRover

RUN echo ${versionRover} > version.txt


# There is no latest git package for centos 7. So building it from source using docker multi-stage builds
# also speed-up sub-sequent builds


###########################################################
# base tools and dependencies
###########################################################
FROM ubuntu:bionic as base

RUN apt-get update && \
    apt-get install -y \
        #libtirpc \
        python3 \
        #python3-libs \
        python3-pip \
        python3-setuptools \
        unzip \
        bzip2 \
        openssh-client \
        openssl \
        man \
        ansible && \
    apt-get upgrade -y


###########################################################
# Getting latest version of terraform-docs
###########################################################
FROM golang:1.13 as terraform-docs

ARG versionTerraformDocs
ENV versionTerraformDocs=${versionTerraformDocs}

RUN GO111MODULE="on" go get github.com/terraform-docs/terraform-docs@${versionTerraformDocs}

###########################################################
# Getting latest version of tfsec
###########################################################
FROM golang:1.13 as tfsec

# to force the docker cache to invalidate when there is a new version
RUN env GO111MODULE=on go get -u github.com/tfsec/tfsec/cmd/tfsec


###########################################################
# CAF rover image
###########################################################
FROM base

# Arguments set during docker-compose build -b --build from .env file
ARG versionTerraform
ARG versionAzureCli
ARG versionKubectl
ARG versionTflint
ARG versionGit
ARG versionJq
ARG versionDockerCompose
ARG versionTfsec
ARG versionAnsible
ARG jenkinsCliUrl

ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=${USER_UID}

ENV USERNAME=${USERNAME} \
    versionTerraform=${versionTerraform} \
    versionAzureCli=${versionAzureCli} \
    versionKubectl=${versionKubectl} \
    versionTflint=${versionTflint} \
    versionJq=${versionJq} \
    versionGit=${versionGit} \
    versionDockerCompose=${versionDockerCompose} \
    versionTfsec=${versionTfsec} \
    versionAnsible=${versionAnsible} \
    jenkinsCliUrl=${jenkinsCliUrl} \
    TF_DATA_DIR="/home/${USERNAME}/.terraform.cache" \
    TF_PLUGIN_CACHE_DIR="/home/${USERNAME}/.terraform.cache/plugin-cache"
     
RUN apt-get install -y \
        git \
        apt-utils \
        zlib1g-dev \
        curl \
        wget \
        gettext \
        bzip2 \
        ca-certificates \ 
        apt-transport-https \
        lsb-release \ 
        gnupg \
        gcc \
        default-jre \
        software-properties-common \
        unzip && \
    #
    # Install Jenkins CLI
    #
    echo "Installing jenkins cli from ${jenkinsCliUrl}..." && \
    curl -L -o /usr/bin/jenkins-cli.jar ${jenkinsCliUrl} && \
    chmod +x /usr/bin/jenkins-cli.jar  && \
    #
    # Install Docker CE CLI.
    #
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - && \
    add-apt-repository \
    "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) \
    stable" && \
    apt-get install -y docker-ce-cli && \
    touch /var/run/docker.sock && \
    chmod 666 /var/run/docker.sock && \
    #
    # Install Terraform
    #
    echo "Installing terraform ${versionTerraform}..." && \
    curl -sSL -o /tmp/terraform.zip https://releases.hashicorp.com/terraform/${versionTerraform}/terraform_${versionTerraform}_linux_amd64.zip 2>&1 && \
    unzip -d /usr/bin /tmp/terraform.zip && \
    chmod +x /usr/bin/terraform && \
    #
    # Install Docker-Compose - required to rebuild the rover from the rover ;)
    #
    echo "Installing docker-compose ${versionDockerCompose}..." && \
    curl -L -o /usr/bin/docker-compose "https://github.com/docker/compose/releases/download/${versionDockerCompose}/docker-compose-Linux-x86_64" && \
    chmod +x /usr/bin/docker-compose && \
    #
    # Install Azure-cli
    #
    echo "Installing azure-cli ${versionAzureCli}..." && \
    curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null && \
    AZ_REPO=$(lsb_release -cs) && \
    add-apt-repository \
    "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli \
    $(lsb_release -cs) \
    main" && \
    apt-get install -y azure-cli=${versionAzureCli}-1~$(lsb_release -cs) && \
    #
    # Install kubectl
    #
    echo "Installing kubectl ${versionKubectl}..." && \
    curl -sSL -o /usr/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/${versionKubectl}/bin/linux/amd64/kubectl && \
    chmod +x /usr/bin/kubectl && \
    #
    # Install Helm
    #
    curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash && \
    #
    # Install jq
    #
    echo "Installing jq ${versionJq}..." && \
    curl -L -o /usr/bin/jq https://github.com/stedolan/jq/releases/download/jq-${versionJq}/jq-linux64 && \
    chmod +x /usr/bin/jq && \
    #
    # Install pre-commit
    #
    echo "Installing pre-commit ..." && \
    python3 -m pip install pre-commit && \ 
    #
    # Install Ansible
    #
    echo "Installing Ansible ..." && \
    pip3 install --user https://github.com/ansible/ansible/archive/stable-${versionAnsible}.tar.gz && \ 
    #
    # Install tflint
    #
    echo "Installing tflint ..." && \
    curl -sSL -o /tmp/tflint.zip https://github.com/terraform-linters/tflint/releases/download/${versionTflint}/tflint_linux_amd64.zip && \
    unzip -d /usr/bin /tmp/tflint.zip && \
    chmod +x /usr/bin/tflint && \
    #
    # Clean-up
    rm -f /tmp/*.zip && rm -f /tmp/*.gz && \
    rm -rfd /tmp/git-${versionGit} && \
    # 
    echo "Creating ${USERNAME} user..." && \
    groupadd docker && \
    useradd --uid $USER_UID -m -G docker ${USERNAME} && \
    usermod -aG docker ${USERNAME} && \
    mkdir -p /tf \
        /home/${USERNAME}/.vscode-server \
        /home/${USERNAME}/.vscode-server-insiders \
        /home/${USERNAME}/.ssh \
        /home/${USERNAME}/.ssh-localhost \
        /home/${USERNAME}/.azure \
        /home/${USERNAME}/.terraform.cache \
        /home/${USERNAME}/.terraform.cache/tfstates && \
    chown -R ${USER_UID}:${USER_GID} /home/${USERNAME} && \
    chmod 777 -R /home/${USERNAME} && \
    chmod 700 /home/${USERNAME}/.ssh && \
    apt-get install -y sudo && \
    echo ${USERNAME} ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/${USERNAME} && \
    chmod 0440 /etc/sudoers.d/${USERNAME} && \
    apt-get clean

COPY --from=tfsec /go/bin/tfsec /bin/
COPY --from=terraform-docs /go/bin/terraform-docs /bin/

WORKDIR /tf/
COPY --from=rover_version version.txt /tf/version.txt

USER ${USERNAME}