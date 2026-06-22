#!/bin/bash

systemctl stop systemd-tmpfiles-setup.service
systemctl disable systemd-tmpfiles-setup.service

# # Install collection(s)
# ansible-galaxy collection install ansible.eda
# ansible-galaxy collection install community.general
# ansible-galaxy collection install ansible.windows
# ansible-galaxy collection install microsoft.ad
dnf install python3 python3-pip -y
pip3 install ansible-sign
# # ## setup rhel user
touch /etc/sudoers.d/rhel_sudoers
echo "%rhel ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers.d/rhel_sudoers
cp -a /root/.ssh/* /home/$USER/.ssh/.
chown -R rhel:rhel /home/$USER/.ssh

git config credential.helper store
touch /home/rhel/.git-credentials
su - rhel -c "echo 'https://gitea:gitea' >> /home/rhel/.git-credentials"
git push -u origin master
su - rhel -c "git config --global user.name gitea"
su - rhel -c "git config --global user.email student@localhost"

sudo mkdir -p /home/rhel/ansible-sign-demo
sudo chown rhel:rhel /home/rhel/ansible-sign-demo
